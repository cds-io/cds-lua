NVIM ?= nvim

.PHONY: all check test lint typecheck

all: check

check: test lint ## what CI would run

# Every cds spec runs inside Neovim: the modules are pure Lua but several
# lean on vim.async, vim.system and vim.uv, and the runner is the one
# calplus uses. Busted is the Lua 5.1 rock, which Neovim's LuaJIT loads.
test: ## busted specs inside Neovim (needs busted for Lua 5.1)
	$(NVIM) --headless -u NONE -i NONE -l spec/busted.lua

lint: ## stylua, luacheck and the language server's type check
	stylua --check lua spec
	luacheck lua spec
	$(MAKE) typecheck

# lua-language-server over lua/, with Neovim's runtime types in the library
# (the script asks the running Neovim for them). LUALS names the binary when
# it is not on PATH, as Mason's is not.
typecheck: ## lua-language-server --check, warnings fail
	$(NVIM) --headless -u NONE -i NONE -l spec/typecheck.lua
