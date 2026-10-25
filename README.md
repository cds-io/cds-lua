# cds-lua

A common library for building Neovim plugins in a functional style: `fp` and
`result` for the vocabulary, `task` for asynchronous work, and the modules
that grew out of the plugins that use them (processes, HTTP, documents,
redraws). It grows as the plugins do.

Keep it simple: each module is pure Lua that names no plugin, every
function answers `value` or `nil, err`, and `nil` alone means failure. The
library grows by addition: a function keeps its contract under its name, and
a different contract gets a different name, so a plugin can check for the
functions it uses and run on any commit that has them. A name a module does
not have fails at the call, in words, naming the module and the key.

This is a learning journey, written in the open. Expect the shape to change.

`:help cds-lua` is the manual: how a plugin takes the library, the Result
convention, the fallback for a missing name, and the modules the plugins call
in common (`fp`, `result`, `task`, `async`, `http`, `redraw`, `activity`). It
is generated from the annotation blocks in the source by
[mini.doc](https://github.com/nvim-mini/mini.doc) (`make doc`), and `make
check` refuses a stale copy. The reference site,
[cds-io.github.io/cds-lua](https://cds-io.github.io/cds-lua/), has one page
per module, every module, from the same annotations through the language
server (`make site`), published on each push to main.

```
make check     # the specs, inside Neovim; stylua; luacheck; the type check; the help file
make doc       # doc/cds-lua.txt
make site      # site/modules/*.md, the reference site's pages
```
