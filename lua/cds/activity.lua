---@tag cds.activity
---@toc_entry What a plugin is waiting on
---@text
--- Tracks every long call a plugin has out, for a statusline segment. A run
--- is tracked from its start to its end; the segment names the runs out with
--- how long each has been out, a User autocmd fires on both edges, and a
--- timer redraws the statusline once a second while anything is out, so the
--- seconds move without the statusline plugin polling. The autocmd name and
--- the clock are parameters, so the module carries nothing of any one plugin.
---@class cds.activity
local M = {}

---@class cds.activity.Options
---@field autocmd string          -- the User autocmd pattern fired on both edges
---@field now? fun(): integer     -- milliseconds; vim.uv.now unless a spec sets one

---@class cds.Activity
---@field runs table<integer, { kind: string, label: string, started: integer }>
---@field next_id integer
---@field timer uv.uv_timer_t?     -- running while anything is out
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

--- Records a run out and returns the id that ends it.
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

--- Forgets a run; nothing for an id already ended.
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

--- Writes the statusline text: `⟳ events google 2s`, every run out in the order
--- they started, joined by ` · `; empty when nothing is out.
---@return string
function Activity:segment()
  local parts = {}
  for _, r in vim.spairs(self.runs) do
    parts[#parts + 1] = ("⟳ %s %s %ds"):format(r.kind, r.label, math.floor((self.now() - r.started) / 1000))
  end
  return table.concat(parts, " · ")
end

--- Whether any run is out.
---@return boolean
function Activity:busy()
  return next(self.runs) ~= nil
end

--- Tracks `task` from now to its completion, however it ends. The end is
--- observed, never awaited: on this nightly a failing child fails the task
--- awaiting it, and the tracker must not die with what it tracks. The finish is
--- scheduled, since the completion callback may run in a fast event, where
--- firing an autocmd is refused.
---@param kind string
---@param label string
---@param task vim.async.Task   -- what cds.Task:run answers
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
