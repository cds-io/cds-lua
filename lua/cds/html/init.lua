-- Reads a W3C technical report from the HTML that the two generators the W3C
-- uses, ReSpec and Bikeshed, emit. The reading goes in four steps, one module
-- each: `cds.html.tokens` scans the text into tags and text, `cds.html.tree`
-- builds the element tree, `cds.html.inline` reads a node's text with its
-- mentions, and `cds.html.blocks` folds the body into the blocks a renderer
-- walks. This file is the surface: the tokenizer's three functions and the
-- reader's two.
local tokens = require("cds.html.tokens")
local blocks = require("cds.html.blocks")

return require("cds.module").wrap("html", {
  tokens = tokens.tokens,
  decode = tokens.decode,
  squash = tokens.squash,
  blocks = blocks.blocks,
  head = blocks.head,
})
