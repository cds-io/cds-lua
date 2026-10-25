NVIM ?= nvim
# mini.doc generates doc/cds-lua.txt from the annotation blocks spec/minidoc.lua
# names: the standalone nvim-mini/mini.doc beside this checkout (CI), or the
# mini.nvim lazy installed, which carries it.
MINIDOC ?= $(firstword $(wildcard ../mini.doc $(HOME)/.local/share/nvim/lazy/mini.doc $(HOME)/.local/share/nvim/lazy/mini.nvim))

.PHONY: all check test lint typecheck doc doc-check site

all: check

check: test lint doc-check ## what CI would run

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
# (spec/luals.lua asks the running Neovim for them). The binary is LUALS, or
# the first of PATH and Mason's install that has one.
typecheck: ## lua-language-server --check, warnings fail
	$(NVIM) --headless -u NONE -i NONE -l spec/typecheck.lua

# The reference site's module pages, from the language server's export of the
# annotations; the Pages workflow builds site/ with Jekyll on every push to
# main. site/modules/ is generated and stays out of git.
site: ## site/modules/*.md, one page per module
	$(NVIM) --headless -u NONE -i NONE -l spec/site.lua

# The help file, generated in place; the tags file it leaves behind is
# ignored, since the plugin manager builds it on install.
doc: ## doc/cds-lua.txt from the annotation blocks, with mini.doc
	$(NVIM) --headless -u NONE -i NONE --cmd "set rtp+=$(MINIDOC)" -l spec/minidoc.lua

# A stale help file fails: regenerate and commit it.
doc-check: doc ## the committed help file is current
	git diff --exit-code -- doc/cds-lua.txt
