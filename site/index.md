---
title: cds-lua
nav_order: 1
permalink: /
---

# cds-lua

Build Neovim plugins that fetch data, handle failures, and refresh buffers
without repeating asynchronous plumbing. `task` composes requests, parsing,
and recovery before starting work; `http` separates transport failures from
HTTP responses; `redraw` preserves the selected item when a listing changes;
`activity` shows running operations in a statusline.

Use only the modules you need. The list and Result helpers, and the startup
API check, live in [cds-lua-fp](https://github.com/cds-io/cds-lua-fp).

## Setup

The asynchronous modules require Neovim 0.13+ with `vim.async` available.
HTTP requires `curl` on PATH. With lazy.nvim, declare the vocabulary dependency
explicitly:

```lua
return {
  "cds-io/cds-lua",
  lazy = true,
  dependencies = { { "cds-io/cds-lua-fp", lazy = true } },
}
```

If you distribute a plugin, include this spec in its `dependencies`. With
another manager, put both libraries on the runtimepath. Check the APIs your
plugin uses at startup with `cds.needs`; the manual (`:help cds-lua`) shows the full check.
It checks availability, not signatures or behavior, and complements your tests.

### HTML parser dependency

`cds.html` uses [lua-gumbo](https://gitlab.com/craigbarnes/lua-gumbo) as its only
HTML parser. Other modules do not require it. Install the Lua 5.1 rock for
Neovim's LuaJIT; a Lua 5.4 build is not compatible:

```sh
luarocks --lua-version=5.1 --local install gumbo 0.5-1
```

Building requires a C99 compiler and Lua 5.1 or LuaJIT development headers.
On macOS, install the Xcode Command Line Tools (`xcode-select --install`) and
LuaRocks with Lua 5.1/LuaJIT headers. On Linux, install a C toolchain, LuaRocks,
and your distribution's Lua 5.1 development package (for example,
`build-essential luarocks liblua5.1-0-dev` on Debian/Ubuntu).

For a local rock installation, add its paths near the start of `init.lua`,
before using HTML conversion:

```lua
local rocks = vim.fn.expand("~/.luarocks")
package.path = rocks .. "/share/lua/5.1/?.lua;" .. rocks .. "/share/lua/5.1/?/init.lua;" .. package.path
package.cpath = rocks .. "/lib/lua/5.1/?.so;" .. package.cpath
```

Use your actual rock tree instead of `~/.luarocks` if you installed elsewhere.
Plugin managers that already expose that Lua 5.1 tree need no extra path setup.
Check inside Neovim with `:lua print(require("gumbo").VERSION)`; the tested
version is `0.5`. Missing or incompatible native modules produce an installation
error when parsing is first requested; there is no fallback parser.

## Start with a small pipeline

This example needs no network. A real producer can await a process or HTTP
request; the validation and transformation steps stay the same.

```lua
local Task = require("cds.task")
local value, err = Task.of(3)
  :ensure(function(n) return n > 0 end, "expected a positive number")
  :map(function(n) return "count: " .. n end)
  :run():wait(1000)
assert(value == "count: 3" and err == nil)
```

Tasks are lazy: `run()` starts a fresh execution and returns a native handle.
`wait()` is for synchronous scripts and tests. In a plugin, observe completion
with `on_complete`, or await the handle inside asynchronous code. The manual
has a complete HTTP → validation → JSON → buffer example, including errors
and scheduling editor updates.

Result functions return a value or `nil, err`; `false` is a valid value.
Tasks test the error slot instead, so `nil` can also be a successful Task
value. `bind_result` adapts Result functions and requires a non-nil success.

## Where to go next

- [Modules](modules/): the complete reference, with examples from the source
  annotations. Start with task for the fetch-and-display workflow, redraw for
  preserving selection, and activity for a statusline integration.
- `:help cds-lua` in Neovim: the tutorial, startup check, and common APIs.
- `:help cds-lua-fp`: the pure Lua vocabulary and capability checks.
- [Source](https://github.com/cds-io/cds-lua): `make check` verifies specs,
  formatting, lint, types, and help freshness. Edit the source annotations,
  then run `make doc` for help or `make site` for the reference pages.
