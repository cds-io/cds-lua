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
