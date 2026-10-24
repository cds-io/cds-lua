-- The one module that names vim.async. It is new in Neovim 0.13 and may still
-- change before that release; every caller goes through here, so a rename
-- is a one-file fix.
--
-- The types are declared here too, as the four functions the family calls.
-- vim.async's own annotations are written over variadic generics (`R...`),
-- which the language server (3.19) cannot follow: every `return nil, err`
-- inside a run and every two-value await came back as a type error. The
-- declaration below says what our callers rely on, a step that answers a
-- value and an error, and nothing about how many values a task carries.
assert(vim.async, "requires Neovim 0.13+ (vim.async)")

--- A step in the Result convention: a value, or nil and its error.
---@alias cds.async.Step fun(...: any): any, any

---@class cds.async
---@field run fun(fn: cds.async.Step, ...: any): vim.async.Task       -- starts the step as a task
---@field await fun(...: any): any, any                              -- a task, or (argc, callback-taking fn, args...)
---@field timeout fun(ms: integer, task: vim.async.Task): any, any  -- the task's answer, or an error at the deadline
---@field semaphore fun(permits: integer): vim.async.Semaphore

return vim.async --[[@as cds.async]]
