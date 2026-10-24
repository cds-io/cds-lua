-- Type check: `nvim -l spec/typecheck.lua`. Runs lua-language-server's
-- --check over lua/ with Neovim's own runtime types in the library, which is
-- the one path only Neovim knows (vim.env.VIMRUNTIME), so the configuration
-- is written here rather than committed. The exit code is the server's: 1
-- when anything at Warning or above is found.
local runtime = vim.env.VIMRUNTIME
local config = vim.fn.tempname() .. ".luarc.json"
vim.fn.writefile({
  vim.json.encode({
    ["runtime.version"] = "LuaJIT",
    ["workspace.library"] = { runtime .. "/lua", "${3rd}/luv/library" },
    ["workspace.ignoreDir"] = { "spec", ".git" },
    ["workspace.checkThirdParty"] = false,
    ["diagnostics.globals"] = { "vim" },
  }),
}, config)
local server = vim.env.LUALS or "lua-language-server"
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local result = vim.system({ server, "--check", root, "--configpath", config, "--checklevel", "Warning" }):wait()
io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
os.exit(result.code)
