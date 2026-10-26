---@tag cds.command
---@toc_entry Command orchestration
---@text
--- Declare a command's argument reader, work and presentation together.
--- register installs commands and optional keys; the shared boundary reports
--- returned errors and exceptions once. read runs at invocation, so the caller
--- can capture buffer identity and cursor position before asynchronous work.
---
--- >lua
---   require("cds.command").register({ {
---     name = "ExampleCount", desc = "Count current buffer lines", keys = { "<leader>ec" },
---     read = function() return vim.api.nvim_get_current_buf() end,
---     run = function(buf) return vim.api.nvim_buf_line_count(buf) end,
---     present = function(count) vim.notify(tostring(count)) end,
---   } })
--- <
--- run returns value, err; only a non-nil error slot means failure, so actions
--- returning nothing and values such as false work too. async=true runs work
--- as a cds Task and schedules presentation after completion. Each invocation
--- captures its own input. Command-specific validation and confirmation stay
--- in the caller. notify can route failures through a plugin's configured
--- notifier; otherwise vim.notify is used. Re-registering a command replaces its definition and keys.

---@class cds.command
local M = {}
local Task = require("cds.task")
local installed = {}

---@class cds.command.Spec
---@field name string
---@field run fun(input: any): any, any
---@field read? fun(args: vim.api.keyset.create_user_command.command_args): any, any
---@field present? fun(value: any, input: any)
---@field desc string?
---@field nargs? string|integer
---@field complete? string|function
---@field bang boolean?
---@field range? boolean|integer|string
---@field keys string[]?
---@field async boolean?
---@field notify? fun(message: string, level: integer) -- defaults to vim.notify

---@param err any
---@param spec cds.command.Spec
local function report(err, spec)
  (spec.notify or vim.notify)(
    type(err) == "table" and (err.message or vim.inspect(err)) or tostring(err),
    vim.log.levels.ERROR
  )
end

---@param spec cds.command.Spec
---@param value any
---@param err any
---@param input any
local function present(spec, value, err, input)
  if err ~= nil then
    report(err, spec)
    return
  end
  if spec.present then
    local ok, failure = pcall(spec.present, value, input)
    if not ok then
      report(failure, spec)
    end
  end
end

---@class cds.command.ActivityOptions
---@field kind string
---@field label string|fun(input: any): string
---@field window? fun(input: any): integer? -- captured target; omit for tracking only

-- Shared across compositors so overlapping commands in one window restore its
-- original statusline only after the last operation finishes.
local feedback = {}

--- Combined Activity text for temporary command feedback in a window.
---@param win integer
---@return string
function M.activity_segment(win)
  local state = feedback[win]
  if not state then
    return ""
  end
  local parts = {}
  for _, entry in ipairs(state.entries) do
    local segment = entry.activity:segment()
    if segment ~= "" then
      parts[#parts + 1] = segment
    end
  end
  return table.concat(parts, " · ")
end

---@param activity cds.Activity
---@param win integer?
---@return fun()
local function show_activity(activity, win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return function() end
  end
  local state = feedback[win]
  if not state then
    local previous = vim.wo[win].statusline
    state = {
      previous = previous,
      statusline = (previous ~= "" and previous or vim.go.statusline)
        .. (" %%{v:lua.require('cds.command').activity_segment(%d)}"):format(win),
      entries = {},
    }
    feedback[win] = state
    vim.wo[win].statusline = state.statusline
  end
  local entry
  for _, candidate in ipairs(state.entries) do
    if candidate.activity == activity then
      entry = candidate
      break
    end
  end
  if not entry then
    entry = { activity = activity, count = 0 }
    state.entries[#state.entries + 1] = entry
  end
  entry.count = entry.count + 1
  return function()
    entry.count = entry.count - 1
    if entry.count == 0 then
      for i, candidate in ipairs(state.entries) do
        if candidate == entry then
          table.remove(state.entries, i)
          break
        end
      end
    end
    if #state.entries == 0 then
      feedback[win] = nil
      if vim.api.nvim_win_is_valid(win) and vim.wo[win].statusline == state.statusline then
        vim.wo[win].statusline = state.previous
      end
    end
  end
end

--- Return a shallow copy of spec with async work tracked by activity. The
--- original spec and tracker are retained by reference, never deep-copied.
--- Tracking covers run; read and present keep cds.command's usual boundaries.
--- Returned errors and exceptions finish tracking before register reports them.
--- An optional window callback enables temporary statusline feedback, restored
--- after all overlapping commands finish. Closing the window is safe; a user's
--- replacement statusline is preserved. The compositor never changes focus.
---
--- Capture buffer/window identities in read, before yielding. The plugin owns
--- output rendering, validity checks and any decision to reopen a closed view.
--- Omit window when using activity:segment() in a custom statusline instead.
--- >lua
---   local command = require("cds.command")
---   local activity = require("cds.activity").new({ autocmd = "ExampleActivity" })
---   command.register({ command.with_activity(activity, {
---     kind = "fetch", label = function(input) return input.url end,
---     window = function(input) return input.win end,
---   }, {
---     name = "ExampleFetch", nargs = 1,
---     read = function(args)
---       return { url = args.args, buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() }
---     end,
---     run = function(input) return require("cds.http").request({ url = input.url }) end,
---     present = function(response, input)
---       if vim.api.nvim_buf_is_valid(input.buf) then
---         vim.api.nvim_buf_set_lines(input.buf, 0, -1, false, vim.split(response.body, "\n"))
---       end
---     end,
---   }) })
--- <
---@param activity cds.Activity
---@param opts cds.command.ActivityOptions
---@param spec cds.command.Spec
---@return cds.command.Spec
function M.with_activity(activity, opts, spec)
  local composed = vim.tbl_extend("force", {}, spec)
  composed.async = true
  composed.run = function(input)
    local label = opts.label
    if type(label) == "function" then
      label = label(input)
    end
    local win = opts.window and opts.window(input) or nil
    local id = activity:begin(opts.kind, label)
    local release = show_activity(activity, win)
    local ok, value, err = pcall(spec.run, input)
    release()
    activity:finish(id)
    if not ok then
      return nil, value
    end
    return value, err
  end
  return composed
end

--- Register commands with optional normal-mode mappings to their names.
---@param specs cds.command.Spec[]
function M.register(specs)
  for _, spec in ipairs(specs) do
    local rhs = "<Cmd>" .. spec.name .. "<CR>"
    for _, key in ipairs(installed[spec.name] or {}) do
      if vim.fn.maparg(key, "n", false, true).rhs == rhs then
        vim.keymap.del("n", key)
      end
    end
    installed[spec.name] = vim.deepcopy(spec.keys or {})
    vim.api.nvim_create_user_command(spec.name, function(args)
      local ok, input, read_err = pcall(spec.read or function(value)
        return value
      end, args)
      if not ok or read_err ~= nil then
        report(not ok and input or read_err, spec)
        return
      end
      if spec.async then
        Task.new(function()
          return spec.run(input)
        end)
          :run()
          :on_complete(function(exception, value, err)
            vim.schedule(function()
              present(spec, value, exception or err, input)
            end)
          end)
      else
        local ran, value, err = pcall(spec.run, input)
        if ran then
          present(spec, value, err, input)
        else
          report(value, spec)
        end
      end
    end, {
      desc = spec.desc,
      nargs = spec.nargs or 0,
      complete = spec.complete,
      bang = spec.bang,
      range = spec.range,
      force = true,
    })
    for _, key in ipairs(spec.keys or {}) do
      vim.keymap.set("n", key, "<Cmd>" .. spec.name .. "<CR>", { silent = true, desc = spec.desc })
    end
  end
end

return require("cds.module").wrap("command", M)
