---@tag cds.async
---@toc_entry vim.async, named once
---@text
--- The one module that names vim.async. It is new in Neovim 0.13 and may
--- still change before that release; every caller goes through here, so a
--- rename is a one-file fix. The module is vim.async itself, under a type
--- declared here as the four functions the family calls, each a step in the
--- Result convention: a value, or nil and its error. vim.async's own
--- annotations are variadic generics the language server cannot follow.

assert(vim.async, "requires Neovim 0.13+ (vim.async)")

---@alias cds.async.Step fun(...: any): any, any  -- a value, or nil and its error

---@class cds.async
---@field run fun(fn: cds.async.Step, ...: any): vim.async.Task       -- starts the step as a task
---@field await fun(...: any): any, any                              -- a task, or (argc, callback-taking fn, args...)
---@field timeout fun(ms: integer, task: vim.async.Task): any, any  -- the task's answer, or an error at the deadline
---@field semaphore fun(permits: integer): vim.async.Semaphore

return vim.async --[[@as cds.async]]
