# cds-lua

A common library for building Neovim plugins in a functional style: `fp` and
`result` for the vocabulary, `task` for asynchronous work, and the modules
that grew out of the plugins that use them (processes, HTTP, documents,
redraws). It grows as the plugins do.

Keep it simple: each module is pure Lua that names no plugin, every
function answers `value` or `nil, err`, and `nil` alone means failure.

This is a learning journey, written in the open. Expect the shape to change.

```
make check     # the specs, inside Neovim; stylua; luacheck
```
