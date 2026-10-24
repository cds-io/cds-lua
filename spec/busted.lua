-- Test entry point: `nvim -l spec/busted.lua [busted args]`. Runs busted inside
-- Neovim so specs get the real `vim.*` API. Busted and its dependencies are the
-- Lua 5.1 rocks (`luarocks --lua-version=5.1 install busted`), which is the ABI
-- Neovim's LuaJIT loads.
local rocks = vim.fn.expand("~/.luarocks")
package.path = table.concat({
  rocks .. "/share/lua/5.1/?.lua",
  rocks .. "/share/lua/5.1/?/init.lua",
  package.path,
}, ";")
package.cpath = rocks .. "/lib/lua/5.1/?.so;" .. package.cpath
require("busted.runner")({ standalone = false })
