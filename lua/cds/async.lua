---@tag cds.async
---@toc_entry Callback and native Task interop
---@text
--- Use Task for composable workflows; use cds.async when adapting a callback
--- API, awaiting a native handle, or sharing a semaphore. This module exports
--- vim.async directly with narrower types for the functions used by cds-lua.
--- Keeping the dependency here limits the changes needed as vim.async evolves.
--- It requires Neovim 0.13+ with vim.async available.
---
--- For example, suspend a task until a scheduled callback completes: >lua
---
---   local async = require("cds.async")
---   local run = async.run(function()
---     async.await(1, function(done) vim.defer_fn(done, 10) end)
---     return "ready"
---   end)
---   assert(run:wait(1000) == "ready")
--- <
--- In the callback form of await, the first argument is the position where
--- await inserts its completion callback into the function's arguments. In
--- this example it is the function's only argument. To await a native Task,
--- pass the handle directly: async.await(run), from inside another task.
--- Native async functions preserve their own return conventions; the
--- value-or-error convention belongs to the functions you run through them.

assert(vim.async, "requires Neovim 0.13+ (vim.async)")

---@alias cds.async.Step fun(...: any): any, any  -- a value, or nil and its error

---@class cds.async
---@field run fun(fn: cds.async.Step, ...: any): vim.async.Task       -- starts the step as a task
---@field await fun(...: any): any, any                              -- a task, or (argc, callback-taking fn, args...)
---@field timeout fun(ms: integer, task: vim.async.Task): any, any  -- the task's answer, or an error at the deadline
---@field semaphore fun(permits: integer): vim.async.Semaphore

return vim.async --[[@as cds.async]]
