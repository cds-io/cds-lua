# cds-lua

A common library for building Neovim plugins in a functional style: `fp` and
`result` for the vocabulary, `task` for asynchronous work, and the modules
that grew out of the plugins that use them (processes, HTTP, documents,
redraws). It grows as the plugins do.

Keep it simple: each module is pure Lua that names no plugin, every
function answers `value` or `nil, err`, and `nil` alone means failure. The
library grows by addition: a function keeps its contract under its name, and
a different contract gets a different name, so a plugin can check for the
functions it uses and run on any commit that has them.

This is a learning journey, written in the open. Expect the shape to change.

```
make check     # the specs, inside Neovim; stylua; luacheck
```
