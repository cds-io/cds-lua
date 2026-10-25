---@tag cds.activity
---@toc_entry Tracking running work
---@text
--- Show which operations are still running and how long they have taken,
--- without making a statusline poll each request. A tracker records active
--- runs, emits a User event when work starts or finishes, and redraws the
--- statusline every second while busy. Labels and event names belong to the
--- caller, so multiple plugins can use separate trackers.
---
--- Track a Task and display its status ~
--- This example uses a short delayed task, so it works without a server. It
--- replaces the current statusline with a file name and the activity segment;
--- in a plugin, expose segment() to the user's statusline configuration instead.
--- >lua
---   local Task = require("cds.task")
---   local async = require("cds.async")
---   local activity = require("cds.activity").new({ autocmd = "ExampleActivity" })
---   _G.example_activity = function() return activity:segment() end
---   vim.o.statusline = "%f %{v:lua.example_activity()}"
---
---   local work = Task.new(function()
---     async.await(1, function(done) vim.defer_fn(done, 1500) end)
---     return "done"
---   end)
---   local run = activity:track("refresh", "example", work:run())
---   run:on_complete(function(exception, _, err)
---     vim.schedule(function()
---       if exception or err then
---         vim.notify(tostring(exception or err), vim.log.levels.ERROR)
---       end
---     end)
---   end)
--- <
--- track returns the same native handle and removes the entry on success or
--- failure. It observes completion; it does not consume or recover errors for
--- the caller. The segment becomes empty when all work finishes. For work
--- without a Task handle, pair begin(kind, label) with finish(id), including
--- every error path. Use the User event for other UI that needs to react to
--- busy-state changes.
---@class cds.activity

local M = {}

---@class cds.activity.Options
---@field autocmd string          -- the User autocmd pattern fired on both edges
---@field now? fun(): integer     -- milliseconds; vim.uv.now unless a spec sets one

---@class cds.Activity
---@field runs table<integer, { kind: string, label: string, started: integer }>
---@field next_id integer
---@field timer uv.uv_timer_t?     -- running while operations are active
---@field pattern string
---@field now fun(): integer
local Activity = {}
Activity.__index = Activity

--- Makes a tracker that fires `opts.autocmd` on both edges of every run.
---@param opts cds.activity.Options
---@return cds.Activity
function M.new(opts)
  vim.validate("autocmd", opts.autocmd, "string")
  return setmetatable({
    runs = {},
    next_id = 0,
    timer = nil,
    pattern = opts.autocmd,
    now = opts.now or vim.uv.now,
  }, Activity)
end

function Activity:fire()
  vim.api.nvim_exec_autocmds("User", { pattern = self.pattern, modeline = false })
end

function Activity:stop_timer()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
end

--- Records an active operation and returns the id to pass to finish.
---@param kind string    -- what is running: "schedule", "events", "complete"
---@param label string   -- who: the adapter's name
---@return integer id
function Activity:begin(kind, label)
  self.next_id = self.next_id + 1
  self.runs[self.next_id] = { kind = kind, label = label, started = self.now() }
  if not self.timer then
    self.timer = vim.uv.new_timer()
    self.timer:start(
      1000,
      1000,
      vim.schedule_wrap(function()
        if next(self.runs) == nil then
          self:stop_timer()
          return
        end
        vim.cmd.redrawstatus()
      end)
    )
  end
  self:fire()
  return self.next_id
end

--- Removes an operation; an id already finished has no effect.
---@param id integer
function Activity:finish(id)
  if not self.runs[id] then
    return
  end
  self.runs[id] = nil
  if next(self.runs) == nil then
    self:stop_timer()
  end
  self:fire()
end

--- Returns statusline text such as `⟳ events google 2s`, with active operations
--- in start order, joined by ` · `; empty when no work is running.
---@return string
function Activity:segment()
  local parts = {}
  for _, r in vim.spairs(self.runs) do
    parts[#parts + 1] = ("⟳ %s %s %ds"):format(r.kind, r.label, math.floor((self.now() - r.started) / 1000))
  end
  return table.concat(parts, " · ")
end

--- Whether any tracked operation is still running.
---@return boolean
function Activity:busy()
  return next(self.runs) ~= nil
end

--- Tracks a native Task until it completes, on success or failure, and returns
--- the same handle. Observes completion without awaiting or recovering errors.
--- Schedules finish on the main loop because firing an autocmd is forbidden
--- in a fast-event callback.
---@param kind string
---@param label string
---@param task vim.async.Task   -- the handle returned by cds.Task:run
---@return vim.async.Task task
function Activity:track(kind, label, task)
  local id = self:begin(kind, label)
  task:on_complete(function()
    vim.schedule(function()
      self:finish(id)
    end)
  end)
  return task
end

--- Forgets every run; for the specs.
function Activity:reset()
  self.runs = {}
  self:stop_timer()
end

return require("cds.module").wrap("activity", M)
