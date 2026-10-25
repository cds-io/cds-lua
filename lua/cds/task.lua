---@tag cds-lua
---@text
--- cds-lua helps Neovim plugin authors fetch data, handle failures, and
--- refresh the editor without repeating the same asynchronous plumbing.
--- Tasks let you compose a request, validation, parsing, and recovery before
--- starting the work. HTTP keeps transport errors separate from response
--- statuses. Redraw preserves the selected item when rows move, and activity
--- turns running work into a statusline segment.
---
--- Use the modules you need. The pure Lua list and Result helpers live in
--- cds-lua-fp (|cds-lua-fp|), a dependency that also supplies |cds.needs| for
--- checking required APIs before a plugin starts.
---
--- Requirements and setup ~
--- The asynchronous modules require Neovim 0.13+ with vim.async available;
--- HTTP also requires curl on PATH. With lazy.nvim, declare both libraries
--- explicitly so the vocabulary is available when cds-lua loads: >lua
---
---   return {
---     "cds-io/cds-lua",
---     lazy = true,
---     dependencies = { { "cds-io/cds-lua-fp", lazy = true } },
---   }
--- <
--- For a plugin you distribute, put this library spec in your plugin's
--- dependencies. Other managers must put both libraries on the runtimepath.
---
--- Check the APIs your plugin uses before registering commands. A declaration
--- can live in lua/example/needs.lua; this self-contained startup check uses
--- the same table directly: >lua
---
---   local ok, needs = pcall(require, "cds.needs")
---   if not ok then
---     vim.notify("example.nvim: install cds-io/cds-lua-fp", vim.log.levels.ERROR)
---     return
---   end
---   local problem = needs.check("example.nvim", {
---     task = { "new" },
---     http = { "request", "status" },
---   })
---   if problem then
---     vim.notify(problem, vim.log.levels.ERROR)
---     return
---   end
---   -- Register the plugin's commands here.
--- <
--- This checks that names exist, not their signatures or behavior. Functions
--- keep their contracts under their names; different contracts get new names.
--- The check complements your plugin's tests and dependency constraints.
---
--- Values and errors ~
--- Result-returning functions use value or nil, err: nil in the first slot
--- means failure, false is a valid value, and failures should carry an error.
--- Task composition instead tests the error slot: a non-nil error is failure;
--- nil and false can both be successful Task values. Task.of_result and
--- Task:bind_result adapt the Result convention, so they require a non-nil
--- success value. Procedures such as redraw.restore return no result.
---
--- Start with the complete example under |cds.task|, then use the module
--- recipes below. This manual covers task, async, HTTP, redraw, and activity.
--- The reference site https://cds-io.github.io/cds-lua/ covers every module,
--- including OAuth, secrets, processes, dates, and images.
---
---@toc

---@tag cds.task
---@toc_entry Tasks
---@text
--- A Task describes asynchronous work without starting it. Build a pipeline
--- once, add validation or recovery, then call run to start a fresh execution.
--- This keeps the request and its error handling together instead of spreading
--- them across callbacks. Tasks wrap vim.async; run returns its native handle.
---
--- Fetch JSON into a scratch buffer ~
--- Run this after installing the dependencies above. It fetches an example
--- JSON document, rejects non-200 responses, decodes the body, and displays it.
--- Transport errors are tables; parser errors here are strings. Normalize them
--- before adding context, rather than assuming every error has a message field.
--- >lua
---   local Task = require("cds.task")
---   local http = require("cds.http")
---
---   local function parse_json(response)
---     local ok, value = pcall(vim.json.decode, response.body)
---     if not ok then
---       return nil, "invalid JSON: " .. tostring(value)
---     end
---     return value
---   end
---
---   local fetch = Task.new(function()
---     return http.request({ method = "GET", url = "https://httpbin.org/json" })
---   end)
---     :ensure(function(response) return response.status == http.status.OK end,
---       function(response) return "HTTP " .. response.status end)
---     :bind_result(parse_json)
---     :map_err(function(err)
---       local message = type(err) == "table" and err.message or tostring(err)
---       return "loading example JSON: " .. message
---     end)
---
---   local run = fetch:run()
---   run:on_complete(function(exception, value, err)
---     -- Completion may be in a fast event; schedule editor changes.
---     vim.schedule(function()
---       local problem = exception or err
---       if problem ~= nil then
---         vim.notify(tostring(problem), vim.log.levels.ERROR)
---         return
---       end
---       local buf = vim.api.nvim_create_buf(false, true)
---       vim.api.nvim_buf_set_lines(buf, 0, -1, false,
---         vim.split(vim.inspect(value), "\n", { plain = true }))
---       vim.api.nvim_set_current_buf(buf)
---     end)
---   end)
--- <
--- The callback's first argument is the native task's exception, followed by
--- the Task's value and error. Task:run converts evaluation exceptions into
--- the returned error slot. Use async.await(run) inside asynchronous code;
--- run:wait(timeout_ms) is useful in synchronous scripts and tests. Both return
--- value, err. Keep the handle when you need to observe completion or track it
--- with |cds.Activity:track()|.
---
--- Choosing a composition step ~
--- Use map for a plain value, bind_result for value-or-error functions, and
--- bind when the next step returns another Task. recover returns a replacement
--- Task on failure; map_err only changes the error. These examples need no
--- network and can be run independently: >lua
---
---   local Task = require("cds.task")
---   local function positive(n)
---     if n <= 0 then return nil, "expected a positive number" end
---     return n
---   end
---   local value, err = Task.of(3)
---     :map(function(n) return n * 2 end)
---     :bind_result(positive)
---     :bind(function(n) return Task.of("count: " .. n) end)
---     :run():wait(1000)
---   assert(value == "count: 6" and err == nil)
---
---   local fallback = Task.of(-1):bind_result(positive)
---     :recover(function(_) return Task.of(0) end)
---     :run():wait(1000)
---   assert(fallback == 0)
--- <
--- recover also catches exceptions from earlier steps; map_err transforms only
--- returned errors. To catch a thrown exception, use recover. When a pipeline
--- touches the editor before completion, put on_main before that step if an
--- earlier producer can resume in a fast event.

local async = require("cds.async")
---@class cds.Task
---@field package evaluate fun(): any, any   -- read by the combinators, in this file only
local Task = {}
Task.__index = Task

--- Makes a Task of fn, which may yield and returns (value, err). Exceptions
--- become errors at run.
---@param fn fun(): any, any
---@return cds.Task
function Task.new(fn)
  return setmetatable({ evaluate = fn }, Task)
end

--- Makes a Task that succeeds with `value`, including nil or false.
---@param value any
---@return cds.Task
function Task.of(value)
  return Task.new(function()
    return value
  end)
end

--- Makes a Task that fails with `err`, which must not be nil.
---@param err any
---@return cds.Task
function Task.fail(err)
  assert(err ~= nil, "a task error must not be nil")
  return Task.new(function()
    return nil, err
  end)
end

--- Lifts a Result (value, or nil and err) into a Task. A refusal must carry its
--- error, as Task.fail requires.
---@param value any
---@param err any
---@return cds.Task
function Task.of_result(value, err)
  if value == nil then
    return Task.fail(err)
  end
  return Task.of(value)
end

--- On success, calls `fn` with the value and evaluates the Task it returns.
--- On failure, preserves the error and skips fn.
---@param fn fun(value: any): cds.Task
---@return cds.Task
function Task:bind(fn)
  return Task.new(function()
    local value, err = self.evaluate()
    if err ~= nil then
      return nil, err
    end
    return fn(value).evaluate()
  end)
end

--- Calls a Result-returning function on success. fn must return a non-nil
--- value, or nil and an error; that error fails the resulting Task.
---@param fn fun(value: any): any, any
---@return cds.Task
function Task:bind_result(fn)
  return self:bind(function(value)
    return Task.of_result(fn(value))
  end)
end

--- Transforms a successful value with fn. Its return is a plain value, not
--- a Result or another Task. On failure, preserves the error and skips fn.
---@param fn fun(value: any): any
---@return cds.Task
function Task:map(fn)
  return self:bind(function(value)
    return Task.of(fn(value))
  end)
end

--- Runs fn for its effect and passes the value on unchanged: a step that
--- records or reports what flowed through it, without a map that has to
--- remember to return its input.
---@param fn fun(value: any)
---@return cds.Task
function Task:tap(fn)
  return self:map(function(value)
    fn(value)
    return value
  end)
end

--- Passes the value on when pred holds for it; otherwise fails. `reason` is the
--- error, or a function of the value that builds it, for the message that wants
--- to quote what was wrong.
---@param pred fun(value: any): boolean
---@param reason any|fun(value: any): any
---@return cds.Task
function Task:ensure(pred, reason)
  return self:bind(function(value)
    if pred(value) then
      return Task.of(value)
    end
    return Task.fail(type(reason) == "function" and reason(value) or reason)
  end)
end

--- Transforms a returned error with fn, for example to add the request name.
--- Successful values pass through unchanged. This does not catch exceptions;
--- use recover when a step may throw. fn must return a non-nil error.
---@param fn fun(err: any): any
---@return cds.Task
function Task:map_err(fn)
  return Task.new(function()
    local value, err = self.evaluate()
    if err ~= nil then
      return nil, fn(err)
    end
    return value
  end)
end

--- On failure, calls fn with the error and evaluates the replacement Task
--- it returns. Successful values pass through unchanged. Also catches thrown
--- exceptions from earlier steps before they can fail a native child task.
---@param fn fun(err: any): cds.Task
---@return cds.Task
function Task:recover(fn)
  return Task.new(function()
    local ok, value, err = pcall(self.evaluate)
    if not ok then
      err = value
    end
    if err ~= nil then
      return fn(err).evaluate()
    end
    return value
  end)
end

--- Resumes composition on Neovim's main loop after a fast-event producer.
---@return cds.Task
function Task:on_main()
  return Task.new(function()
    local value, err = self.evaluate()
    if vim.in_fast_event() then
      async.await(1, vim.schedule)
    end
    return value, err
  end)
end

--- Evaluates while holding an existing semaphore, shared across the batch.
---@param semaphore vim.async.Semaphore
---@return cds.Task
function Task:limited(semaphore)
  return Task.new(function()
    return semaphore:with(self.evaluate)
  end)
end

--- Times a successful result. limited(...):timed() includes queue time;
--- timed():limited(...) measures only the time after acquiring the permit.
--- Errors retain their original error channel.
---@param now? fun(): number Nanoseconds; injectable for deterministic checks.
---@return cds.Task
function Task:timed(now)
  now = now or vim.uv.hrtime
  return Task.new(function()
    local started = now()
    local value, err = self.evaluate()
    if err ~= nil then
      return nil, err
    end
    return { value = value, ms = math.floor((now() - started) / 1e6) }
  end)
end

--- Starts a fresh execution and returns a native vim.async.Task handle.
--- Its results are value, err. Observe them with on_complete(exception, value,
--- err), await the handle inside async code, or use wait in a script or test.
---@return vim.async.Task
function Task:run()
  return async.run(function()
    local ok, value, err = pcall(self.evaluate)
    if not ok then
      return nil, value
    end
    return value, err
  end)
end

--- Starts all tasks and joins every run, even on error: remote writes cannot
--- be rolled back by cancelling their siblings. Results retain nil slots via n.
--- Returns the first error in input order only after all runs have settled.
---@param tasks cds.Task[]
---@return cds.Task
function Task.all(tasks)
  local inputs = vim.list_extend({}, tasks)
  return Task.new(function()
    local runs, values, first_error = {}, { n = #inputs }, nil
    for i, task in ipairs(inputs) do
      runs[i] = task:run()
    end
    for i, run in ipairs(runs) do
      local value, err = async.await(run)
      values[i] = value
      if first_error == nil and err ~= nil then
        first_error = err
      end
    end
    if first_error ~= nil then
      return nil, first_error
    end
    return values
  end)
end

return require("cds.module").wrap("task", Task)
