# What the gate needs on the machine: nvim; busted and gumbo 0.5-1 (the
# HTML5 parser the html specs load) as Lua 5.1 rocks in the luarocks user
# tree (`luarocks --lua-version=5.1 --local install busted gumbo 0.5-1`);
# stylua and luacheck (`luarocks --lua-version=5.1 --local install
# luacheck`, found in the user tree when PATH lacks it); lua-language-server
# on PATH or under Mason; mini.doc. The architecture check skips without the
# lua-spec checkout.
NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= $(if $(wildcard $(HOME)/.luarocks/bin/luacheck),$(HOME)/.luarocks/bin/luacheck,luacheck)
# mini.doc generates doc/cds-lua.txt from the annotation blocks spec/minidoc.lua
# names: the standalone nvim-mini/mini.doc beside this checkout (CI), or the
# mini.nvim lazy installed, which carries it.
MINIDOC ?= $(firstword $(wildcard ../mini.doc $(HOME)/.local/share/nvim/lazy/mini.doc $(HOME)/.local/share/nvim/lazy/mini.nvim))
PYTHON ?= python3

.PHONY: all check architecture-check test lint typecheck doc doc-check site

all: check

check: architecture-check test lint doc-check ## what CI would run

# The architecture rules (module size, facade imports, dependency cycles) are
# checked by lua-spec, a sibling checkout the house keeps to itself, with the
# settings in lua-spec.toml here. Without the checkout the target says so and
# passes, so make check holds on any machine.
LUA_SPEC ?= $(wildcard ../lua-spec)

architecture-check: ## module size, facade imports and cycles, through lua-spec
	@if [ -n "$(LUA_SPEC)" ]; then PYTHONPATH="$(LUA_SPEC)" $(PYTHON) -m lua_spec.check; \
	else echo "architecture-check: ../lua-spec not found; skipped"; fi

# Every cds spec runs inside Neovim: the modules are pure Lua but several
# lean on vim.async, vim.system and vim.uv, and the runner is the one
# calplus uses. Busted is the Lua 5.1 rock, which Neovim's LuaJIT loads, and
# so is gumbo, which the html specs parse with; a missing gumbo fails those
# specs with the install command in the message.
test: ## busted specs inside Neovim (needs busted and gumbo for Lua 5.1)
	$(NVIM) --headless -u NONE -i NONE -l spec/busted.lua

lint: ## stylua, luacheck and the language server's type check
	$(STYLUA) --check lua spec
	$(LUACHECK) lua spec
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
