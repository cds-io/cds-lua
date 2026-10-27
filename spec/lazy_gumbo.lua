-- Explicit integration check; not part of the offline Busted suite.
-- LAZY_NVIM_DIR=/path/to/lazy.nvim CDS_LAZY_TEST_ROOT=/fresh/tmp/path nvim
--   --headless -u NONE -i NONE -l spec/lazy_gumbo.lua
-- Requires network access, git, a C compiler and Lazy's LuaRocks build tooling.
local root = assert(vim.env.CDS_LAZY_TEST_ROOT, "set CDS_LAZY_TEST_ROOT to a fresh temporary directory")
local manager = assert(vim.env.LAZY_NVIM_DIR, "set LAZY_NVIM_DIR to a lazy.nvim checkout")
assert(not vim.uv.fs_stat(root), "CDS_LAZY_TEST_ROOT must not already exist")
assert(not pcall(require, "gumbo"), "Gumbo is already on the module path; run with clean LUA_PATH/LUA_CPATH")

local project = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(manager)
vim.go.loadplugins = true -- -u NONE disables plugin loading, including Lazy setup.
require("lazy").setup({
  { dir = project, name = "cds-lua", lazy = true },
  { dir = project .. "/../cds-lua-fp", name = "cds-lua-fp", lazy = true },
}, {
  root = root .. "/plugins",
  lockfile = root .. "/lazy-lock.json",
  local_spec = false,
  pkg = { cache = root .. "/pkg-cache.lua" },
  rocks = { root = root .. "/rocks" },
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  readme = { root = root .. "/readme" },
  performance = { cache = { enabled = false } },
})
require("lazy").install({ wait = true, show = false })

local plugin = assert(require("lazy.core.config").plugins["lua-gumbo"], "cds-lua did not declare Gumbo")
assert(plugin._.pkg and plugin._.pkg.source == "rockspec", "Lazy did not detect Gumbo's rockspec")
assert(plugin.build == "rockspec", "Lazy did not select the rockspec build")

-- Loading cds.html must load its declared dependency without manual path edits.
local html = require("cds.html")
local lines, anchors = html.markdown('<p id="intro">Hello &amp; <em>world</em></p>')
assert(vim.deep_equal({ "Hello \\& *world*" }, lines))
assert(anchors.intro == 1)

local function locate(name, paths)
  for pattern in paths:gmatch("[^;]+") do
    local path = pattern:gsub("%?", (name:gsub("%.", "/")))
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end
local lua = assert(locate("gumbo", package.path), "cannot locate gumbo.lua")
local native = assert(locate("gumbo.parse", package.cpath), "cannot locate Gumbo's native parser")
assert(lua:sub(1, #root) == root, "Gumbo's Lua code was loaded from outside the isolated installation")
assert(native:sub(1, #root) == root, "Gumbo's native parser was loaded from outside the isolated installation")
print(vim.json.encode({ version = require("gumbo").VERSION, lua = lua, native = native, lines = lines }))
