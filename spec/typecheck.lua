-- Type check: `nvim -l spec/typecheck.lua`. Runs lua-language-server's
-- --check over lua/ with Neovim's own runtime types in the library. The exit
-- code is the server's: 1 when anything at Warning or above is found.
local luals = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/luals.lua")
local result = vim
  .system({ luals.server(), "--check", luals.root(), "--configpath", luals.config(), "--checklevel", "Warning" })
  :wait()
io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
os.exit(result.code)
