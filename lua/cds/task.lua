---@tag cds-lua
---@text
--- cds-lua is a common library for Neovim plugins written in a functional
--- style: `task` for asynchronous work, and the modules that grew out of the
--- plugins that use them (processes, HTTP, documents, redraws). The
--- vocabulary they are written in, |cds.fp| for lists and |cds.result| for
--- the Result convention, is the cds-lua-fp rock (|cds-lua-fp|), which this
--- library depends on; |cds.needs|, from the same rock, is how a plugin takes
--- both: it declares the functions it calls, and the check at startup names
--- what the libraries installed lack. Each module is pure Lua that names no
--- plugin; every function answers `value` or `nil, err`, and `nil` alone
--- means failure.
---
--- This manual covers the modules the plugins call in common. The rest (the
--- document readers, OAuth, processes, dates) are documented in their source,
--- which the language server shows on hover, and on the reference site.
---
---@toc

---@tag cds.task
---@toc_entry Tasks
---@text
--- A Task is a lazy asynchronous result over vim.async: a recipe, so nothing
--- runs until |cds.Task:run()|, and a pipeline can be built, combined and
--- handed around as a value. Composition passes one value and one error, in
--- the Result convention; nil and false are valid successes. >lua
---
---   local Task = require("cds.task")
---   Task.new(function()
---     return http.request({ method = "GET", url = url })
---   end)
---     :bind_result(parse)
---     :map_err(function(err) return "the index: " .. err.message end)
---     :run()
--- <

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

--- Makes a Task that answers `value`.
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

--- Passes the value through `fn`, which answers the Task to go on with; an
--- error passes through untouched.
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

--- Binds a step written in the Result convention: fn answers a value, or nil
--- and its error, and the task fails with that error.
---@param fn fun(value: any): any, any
---@return cds.Task
function Task:bind_result(fn)
  return self:bind(function(value)
    return Task.of_result(fn(value))
  end)
end

--- Passes the value through `fn`, which always answers; an error passes through
--- untouched.
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

--- Passes the error through fn; a value passes untouched. This is the step that
--- describes a failure for the reader (what was being fetched, where it was
--- met) without a recover that fails again. Exceptions are not yet errors here;
--- recover is the combinator that catches them.
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

--- Passes the error through `fn`, which answers the Task to go on with; a value
--- passes through untouched. Recovery also catches exceptions, inside the child
--- rather than its awaiter: an uncaught vim.async child failure can cancel its
--- siblings.
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

--- Starts a fresh run and returns the native handle for activity/on_complete.
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
