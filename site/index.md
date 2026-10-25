---
title: cds-lua
nav_order: 1
permalink: /
---

# cds-lua

A common library for Neovim plugins written in a functional style: `task` for
asynchronous work, and the modules that grew out of the plugins that use them
(processes, HTTP, documents, redraws). The vocabulary they are written in,
`cds.fp` for lists and `cds.result` for the Result convention, and the
`cds.needs` check a plugin runs at startup, are the
[cds-lua-fp](https://github.com/cds-io/cds-lua-fp) rock, which this library
depends on. Each module is pure Lua that names no plugin; every function
answers `value` or `nil, err`, and `nil` alone means failure.

The library grows by addition: a function keeps its contract under its name,
and a different contract gets a different name, so a plugin can declare the
functions it uses and run on any commit that has them. A name a module does not
have fails at the call, in words, naming the module and the key.

## Taking the library

A plugin takes it as a lazy.nvim dependency, declared in the `lazy.lua` at its
root, tracking `main`:

```lua
return {
  "cds-io/<plugin>",
  dependencies = { { "cds-io/cds-lua", lazy = true } },
}
```

What the plugin calls is declared in `lua/<plugin>/needs.lua`, by module and
name, and checked at startup by `cds.needs`, from the rock:

```lua
---@type cds.needs.Capabilities
return {
  fp = { "map", "filter" },
  http = { "request", "status" },
}
```

## Reading on

- [Modules](modules/): one page per module, from the annotations in the source.
- `:help cds-lua` inside Neovim: the manual, covering the modules the plugins
  call in common; `:help cds-lua-fp` covers the vocabulary.
- The source: [github.com/cds-io/cds-lua](https://github.com/cds-io/cds-lua).
  `make check` runs the specs inside Neovim, stylua, luacheck, the language
  server's type check and the help file's freshness.
