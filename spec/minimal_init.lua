-- Runs inside `nvim -l` before any spec: put the library and the test fakes
-- on the path so `require("cds.x")` and `require("fakeproc")` both resolve.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/spec/?.lua",
  root .. "/spec/fixtures/lua/?.lua",
  package.path,
}, ";")
