# cds-lua

Build Neovim plugins that fetch data, handle failures, and refresh buffers
without repeating asynchronous plumbing. `task` composes requests, parsing,
and recovery before starting work; `http` separates transport failures from
HTTP responses; `redraw` preserves the selected item when a listing changes;
`activity` shows running operations in a statusline; `pick` owns a keyed floating
selector, including focus restoration and teardown. `persist` handles atomic
file/JSON writes, `scratch` owns persistent buffer/window views, `companion`
attaches sidebars to specific editor windows, and `command` composes argument
reading, work, presentation, and error reporting. `command.with_activity` adds
async execution, Activity tracking, and optional temporary window statusline
feedback to a command spec, including cleanup on failure and overlapping runs.

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

## Shared document readers

`cds.html.document(body, { base = url, page = true })` returns a pure source
contract: `{ markdown, anchors, links, url }` (and the page title as its second
return). Anchors map original HTML IDs, named anchors, and generated heading
slugs to **one-based Markdown lines**. Link spans use one-based lines and
zero-based byte columns (`col` inclusive, `end_col` exclusive). Fragment links
resolve against the base URL, preserving its query. Omit `page` for an HTML
fragment; `page = true` selects main/article/body content. Selection and
conversion never fetch a URL. Retain source-specific citation and tag policy
in the consuming plugin.

`cds.document.prepend(source, header)` shifts anchors when a plugin adds metadata.
`cds.document.anchor(source, fragment, rendered)` maps an explicit or generated
anchor through vellum's block mappings. When a block compresses or wraps several
source lines, navigation lands at the start of that rendered block.

`cds.vellum.render(source.markdown, width, { notify = notify })` returns lines,
highlight/link spans, pending-media state, and source block mappings. It returns
nil when vellum is absent or fails, allowing a plain Markdown fallback. The
optional dependency stays optional. `restyle()` invalidates theme state.
`cds.document_view.new(deps)` owns redraws and bounded image retries; its injected
model guard prevents stale asynchronous rendering from changing another model.

`cds.navigator.new()` creates independent per-window follow guards and history.
`follow(win, target, resolve, open)` accepts web URLs or application tags: the
plugin supplies `resolve(target, callback)` and `open(destination, error, done)`.
Call `done()` only after the destination opens. `remember(win, move)` tracks other
moves, `pop(win)` returns the previous buffer handle/name/view (the handle preserves unnamed buffers), and `jump(win, source,
rendered, fragment)` moves to a document anchor. Call `forget(win)` on window
closure and `reset()` when discarding the session. Native help/tag resolution can
remain in the resolver/open callbacks; the library does not rewrite RFC tags or
install global key mappings.

The document regressions include unchanged fixtures from rssfeedr and rfc.nvim;
the shared library's tests require neither plugin. See
`spec/fixtures/documents/README.md` for their provenance.

Navigation intent supersedes pending work in that window: `jump`, `pop`, and
`remember` invalidate earlier follows automatically. Use `cancel(win)` for
caller-owned navigation, such as sending a link to an external opener. It
preserves history and leaves other windows' pending follows alone. A cancelled
resolver may still finish caching its result, but its callback cannot open it.

The display boundary is typed as `cds.DocumentViewDependencies`,
`cds.DocumentModel`, and `cds.RenderedDocument`. The rendered record contains
`source`, `lines`, `marks`, `styled`, `waiting`, and optional source `blocks`;
river rows and folds remain consumer-owned. `cds.document.rendered(...)`
constructs this record without modifying source or renderer inputs.

`cds.document.target(source, rendered, row, col, opts)` applies one hit-testing
policy to both formats. Positions use one-based rows and zero-based byte
columns. `first = true` selects the leftmost link; otherwise the most specific
cursor span wins, with enclosing links preferred over images. `line` may supply
edited Markdown; unchanged source lines use compiled metadata, including code
fence exclusions. The older `link` and `link_at` entry points remain available.

HTML adapters may choose `region = "body"` with `page = true` and an explicit
`drop` map when metadata outside main/article belongs to the source document.
The default reader policy still prefers main, article, then body.
