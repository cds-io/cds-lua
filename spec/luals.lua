-- The language server behind `make typecheck` and `make site`: where the
-- binary is, and the configuration a run takes. The configuration is written
-- at run time because the one path that matters, Neovim's own runtime
-- (vim.env.VIMRUNTIME), is known only to a running Neovim; a committed
-- .luarc.json could not name it portably.
local M = {}

--- The binary: LUALS when set, else the first of PATH and Mason's install
--- (Neovim's data directory, where :MasonInstall puts it) that has one; a
--- refusal in one line naming all three when none has it.
---@return string
function M.server()
  local mason = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
  for _, candidate in ipairs({ vim.env.LUALS or "", vim.fn.exepath("lua-language-server"), mason }) do
    if candidate ~= "" and vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  io.stderr:write(
    "no lua-language-server: LUALS is "
      .. (vim.env.LUALS or "unset")
      .. ", PATH has none, and Mason's "
      .. mason
      .. " is not there\n"
  )
  os.exit(1)
end

--- A .luarc.json for the library: LuaJIT, Neovim's runtime types, libuv's and
--- the vocabulary rock beside this checkout in the library, spec/ and .git
--- left out.
---@return string path
function M.config()
  local path = vim.fn.tempname() .. ".luarc.json"
  vim.fn.writefile({
    vim.json.encode({
      ["runtime.version"] = "LuaJIT",
      ["workspace.library"] = { vim.env.VIMRUNTIME .. "/lua", "${3rd}/luv/library", M.root() .. "/../cds-lua-fp/lua" },
      ["workspace.ignoreDir"] = { "spec", ".git" },
      ["workspace.checkThirdParty"] = false,
      ["diagnostics.globals"] = { "vim" },
    }),
  }, path)
  return path
end

--- The repository root: the parent of the directory this file is in.
---@return string
function M.root()
  return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
end

return M
