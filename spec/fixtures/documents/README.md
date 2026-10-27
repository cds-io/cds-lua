# Document regression fixtures

- `rssfeedr-page.html`: copied unchanged from rssfeedr `spec/fixtures/page.html`, the Scratch Buffer article “Hot singles in your area: Vol1”, fetched 2026-10-26. Source: https://blog.nerdware.ca/2026/10/24/hot-singles-v1.html .
- `rfc-css-grid-2.html`: copied unchanged from rfc.nvim `spec/fixtures/w3c-css-grid-2.html`. Its opening comment records source, excerpt boundaries and the W3C Document License notice, retained here.

The shared library must read these fixtures without either consuming plugin on its runtime path.

The `.html.document.json` files capture the complete document contracts from
commit `2efa330`'s streaming parser, before switching to Gumbo. Tests compare the
Markdown lines, all anchor rows, link spans, URL and title against these fixed
snapshots. They establish that the real documents retain their output through
the parser migration. Update a snapshot only for an intentional output change.
