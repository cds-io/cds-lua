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
