NVIM ?= nvim

.PHONY: all check test lint

all: check

check: test lint ## what CI would run

# Every cds spec runs inside Neovim: the modules are pure Lua but several
# lean on vim.async, vim.system and vim.uv, and the runner is the one
# calplus uses. Busted is the Lua 5.1 rock, which Neovim's LuaJIT loads.
test: ## busted specs inside Neovim (needs busted for Lua 5.1)
	$(NVIM) --headless -u NONE -i NONE -l spec/busted.lua

lint: ## stylua and luacheck
	stylua --check lua spec
	luacheck lua spec
