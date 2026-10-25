# cds-lua

Build Neovim plugins that fetch data, handle failures, and refresh buffers
without repeating asynchronous plumbing. `task` composes requests, parsing,
and recovery before starting work; `http` separates transport failures from
HTTP responses; `redraw` preserves the selected item when a listing changes;
`activity` shows running operations in a statusline; `pick` owns a keyed floating
selector, including focus restoration and teardown. `persist` handles atomic
file/JSON writes, `scratch` owns persistent buffer/window views, `companion`
attaches sidebars to specific editor windows, and `command` composes argument
reading, work, presentation, and error reporting.

Use only the modules you need. The list and Result helpers, and the startup
API check, live in [cds-lua-fp](https://github.com/cds-io/cds-lua-fp).

<a href="https://dotfyle.com/plugins/cds-io/cds-lua">
    <img src="https://dotfyle.com/plugins/cds-io/cds-lua/shield?style=for-the-badge" alt="Find cds-lua on Dotfyle" />
</a>

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
plugin uses at startup with `cds.needs`; `:help cds-lua` shows the full check.
It checks availability, not signatures or behavior, and complements your tests.

> Need to switch between Neovim versions? [Bob](https://github.com/mordechaihadad/bob)
> installs and switches between stable and nightly builds. Bob’s your uncle!

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

## Documentation and development

- `:help cds-lua`: setup, complete examples, recipes, and the common APIs.
- `:help cds-lua-fp`: list helpers, Result composition, and capability checks.
- [Reference site](https://cds-io.github.io/cds-lua/): every module, generated
  from source annotations through the language server.

Help prose and examples live in source annotation blocks. `mini.doc` generates
the help file; edit the annotations and regenerate it with `make doc`.
The library grows by addition: functions keep their contracts under their
names, and different contracts get different names. This is a learning
project, written in the open.

```
make check     # specs, formatting, lint, type check, and help freshness
make doc       # regenerate doc/cds-lua.txt
make site      # generate site/modules/*.md from annotations
```

## Licence

MIT; see LICENSE.
