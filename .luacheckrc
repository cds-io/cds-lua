std = "luajit"
codes = true
max_line_length = 120
read_globals = { "vim" }
-- Assigning a field of vim (vim.bo[buf].filetype = ..., vim.g.x = ...) is how the
-- Neovim API works, and luacheck reads it as writing a read-only global.
ignore = { "122" }
files["spec/"] = { std = "+busted" }
