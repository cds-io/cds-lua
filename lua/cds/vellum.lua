---@tag cds.vellum
---@toc_entry Optional vellum rendering
---@text
--- Adapt vellum to lines, highlight/link spans, image-pending state and source block mappings. If unavailable or
--- invalid, render returns nil so callers display Markdown. restyle invalidates theme state; forget permits
--- another warning.

-- The article as styled text, when vellum.nvim is installed. Its renderer
-- turns the article's Markdown into lines wrapped to a width, plus the
-- highlight spans that style them, and the item read paints both. The
-- renderer is a module vellum keeps for its own preview, with no promise
-- that it stays as it is, so what comes back is checked here and every
-- surprise comes out as nil: the item read then shows the Markdown itself.
-- vellum is optional, found by pcall(require), so it is neither in needs.lua
-- nor in lazy.lua.
local sources = require("cds.vellum.sources")

local M = {}

-- The widest column of text, as in vellum's own preview.
local MEASURE = 100

-- Whether vellum's highlight groups are defined for the current colorscheme,
-- and whether the reader has been told that vellum failed.
local themed, warned = false, false

-- vellum's renderer and theme, as one record, when it is installed, with
-- its media module when there is one.
local function vellum()
  local found, render = pcall(require, "vellum.render")
  local found_theme, theme = pcall(require, "vellum.theme")
  if found and found_theme then
    local found_media, media = pcall(require, "vellum.media")
    return { render = render, theme = theme, media = found_media and type(media) == "table" and media or nil }
  end
end

-- vellum's count of the output it answered a placeholder for while that
-- output renders (a remote image, through its headless browser). The count
-- only grows; a render that raises it waited on something.
local function waits(toolkit)
  local count = toolkit.media and toolkit.media.pending
  return type(count) == "number" and count or nil
end

-- One of vellum's block anchors: four numbers placing the block's source rows
-- in `page.markdown` and its rendered rows in `page.lines`.
local function anchored(block, page)
  for i = 1, 4 do
    if type(block[i]) ~= "number" then
      return false
    end
  end
  return block[1] >= 0
    and block[1] + block[2] <= #page.markdown
    and block[3] >= 0
    and block[3] + block[4] <= #page.lines
end

-- `markdown` through vellum, `toolkit`, at `width`: the lines, the marks,
-- the waiting and the blocks of render() below, or an error for anything
-- that comes back in a shape not expected.
local function compose(toolkit, markdown, width, cache_dir)
  if not themed then
    toolkit.theme.apply()
    -- Rendered blocks are cached with the groups they were given.
    toolkit.render.reset()
    themed = true
  end
  -- The renderer parses a buffer; this one is never shown.
  local source = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(source, 0, -1, false, sources.materialise(markdown, cache_dir))
  local before = waits(toolkit)
  local ok, lines, rows, margin, blocks = pcall(toolkit.render.render, source, width, MEASURE)
  local after = waits(toolkit)
  vim.api.nvim_buf_delete(source, { force = true })
  assert(ok, lines)
  assert(type(lines) == "table" and type(rows) == "table" and type(margin) == "number", "no lines to show")

  -- vellum counts a span's columns from the text's left edge, and indents
  -- every line by `margin` to centre the text.
  local found = {}
  for row, line in ipairs(lines) do
    assert(type(line) == "string", "a line that is not text")
    for _, span in ipairs(rows[row] or {}) do
      local from, to, group = span[1] + margin, span[2] + margin, span[3]
      assert(from >= 0 and from <= to and to <= #line and type(group) == "string", "a span outside its line")
      -- A wiki link's target is a table; only a target written as text is followed.
      local link = type(span[5]) == "string" and span[5] or nil
      found[#found + 1] = { lnum = row, col = from, end_col = to, hl = group, priority = span[4], link = link }
    end
  end
  assert(type(blocks) == "table", "no block anchors")
  local page = { markdown = markdown, lines = lines }
  for _, block in ipairs(blocks) do
    assert(anchored(block, page), "a block anchor outside the page")
  end
  return lines, found, before ~= nil and after ~= nil and after > before, blocks
end

--- `markdown` (a list of lines) for a window `width` columns wide: the lines
--- to show, the marks { lnum, col, end_col, hl, priority, link } that style
--- them (lines counted from one and byte columns from zero; `link` the target
--- of the link the span is part of), and whether some of it is a placeholder
--- for output vellum is still rendering, so a render a moment later shows
--- more; and vellum's block anchors, each `{ from, count, to, rows }`
--- placing `count` Markdown lines past index `from` at `rows` drawn lines
--- past `to` (both from zero). Nil when vellum is not installed, and nil
--- with one warning when it is and cannot do this. An image whose source is
--- a base64 data URI is handed to vellum as a file under `opts.cache_dir`
--- (cds/images under Neovim's cache directory unless given), since vellum
--- reads paths and http(s) URLs only.
---@param markdown string[]
---@param width integer
---@param opts? { notify: function?, cache_dir: string? }
---@return string[]? lines
---@return cds.DocumentMark[]? marks
---@return boolean? waiting
---@return integer[][]? blocks
function M.render(markdown, width, opts)
  local found = vellum()
  if not found then
    return nil
  end
  local cache_dir = opts and opts.cache_dir or vim.fn.stdpath("cache") .. "/cds/images"
  local ok, lines, marks, waiting, blocks = pcall(compose, found, markdown, width, cache_dir)
  if ok then
    return lines, marks, waiting, blocks
  end
  if not warned then
    warned = true
    local message = "vellum.nvim could not render the document, showing Markdown: "
    local notify = opts and opts.notify or vim.notify
    notify(message .. tostring(lines), vim.log.levels.WARN)
  end
  return nil
end

local generation = 0

--- A colorscheme clears the highlight groups: define them again on the next
--- render. The generation moves, so a memo of rendered lines knows to let
--- the next render through.
function M.restyle()
  themed = false
  generation = generation + 1
end

--- How many times the theme has been invalidated: a key for a memo over
--- render, since the groups a rendering names are defined by the render
--- that follows a restyle.
---@return integer
function M.generation()
  return generation
end

--- The reader is told again, once, should vellum still fail.
function M.forget()
  warned = false
end

return M
