---@tag cds.document
---@toc_entry Document source contract
---@text
--- Pure Markdown documents carry one-based anchor rows and link spans with zero-based byte columns. Explicit HTML
--- anchors take precedence over generated heading slugs. Renderers preserve this source document and map its rows
--- through their block anchors. Link scanning excludes inline code and escaped delimiters; fenced code is
--- excluded from both link and heading metadata.

local M = {}
local scan = require("cds.document.scan")
local rows = require("cds.document.rows")

--- The destination of the Markdown link under byte column `col` (from zero)
--- of `line`: the innermost `[text](href)` whose span covers it, so an
--- image inside a link answers the link; else the innermost `![alt](src)`
--- that does; else a bare `<url>` that does; nil off every link.
---@param line string
---@param col integer
---@return string|nil
function M.link_at(line, col)
  return M.link(M.new({ line }), 1, col)
end

--- Allocate unique names in input order without modifying the bases. Callers
--- supply their own slugs/prefixes and the first duplicate suffix (default 1).
---@param bases string[]
---@param first? integer
---@return string[]
function M.unique_names(bases, first)
  return scan.unique_names(bases, first)
end

--- A heading's text as GitHub writes its anchor: lower-cased, letters,
--- digits, `-` and `_` kept, each space a dash, everything else dropped.
--- Bytes past ASCII are kept, so a heading in another script keeps its
--- letters.
---@param text string
---@return string
function M.slug(text)
  return scan.slug(text)
end

--- The heading of `markdown` (a list of lines) whose slug is `fragment`:
--- its index and its text as it reads; nil when no heading has it.
---@param markdown string[]
---@param fragment string
---@return integer|nil, string|nil
function M.heading(markdown, fragment)
  return scan.heading(markdown, fragment)
end

---@class cds.LinkSpan
---@field lnum integer
---@field col integer
---@field end_col integer
---@field target? string
---@field link? string
---@field kind? string

---@class cds.DocumentLink: cds.LinkSpan
---@field lnum integer -- one-based Markdown line
---@field col integer -- zero-based byte column, inclusive
---@field end_col integer -- zero-based byte column, exclusive
---@field target string
---@field kind string

---@class cds.Document
---@field markdown string[]
---@field anchors table<string, integer> -- anchor name to one-based Markdown line
---@field links cds.DocumentLink[]
---@field url string?

--- Build a source document; explicit anchors override generated heading slugs.
--- Inputs are copied. Links use zero-based byte columns and one-based lines.
---@param markdown string[]
---@param opts? { anchors: table<string, integer>?, url: string? }
---@return cds.Document
function M.new(markdown, opts)
  opts = opts or {}
  local doc = { markdown = {}, anchors = {}, links = {}, url = opts.url }
  local bases, heading_rows, eligible = {}, {}, {}
  local fence
  for row, line in ipairs(markdown) do
    doc.markdown[row] = line
    local marker, rest = line:match("^%s*(```+)(.*)$")
    if not marker then
      marker, rest = line:match("^%s*(~~~+)(.*)$")
    end
    if marker then
      if not fence then
        if marker:sub(1, 1) ~= "`" or not rest:find("`", 1, true) then
          fence = marker
        end
      elseif marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence and rest:match("^%s*$") then
        fence = nil
      end
    elseif not fence then
      eligible[row] = true
      local text = line:match("^#+%s+(.-)%s*$")
      if text then
        bases[#bases + 1], heading_rows[#heading_rows + 1] = scan.slug(scan.plain(text)), row
      end
    end
  end
  for i, name in ipairs(scan.unique_names(bases)) do
    doc.anchors[name] = heading_rows[i]
  end
  local code = scan.paragraph_code(markdown, eligible)
  for row, line in ipairs(markdown) do
    if eligible[row] then
      for _, link in ipairs(scan.scan_links(line, row, code[row] or {})) do
        doc.links[#doc.links + 1] = link
      end
    end
  end
  for name, row in pairs(opts.anchors or {}) do
    doc.anchors[name] = row
  end
  return doc
end

--- Add a plugin-specific header, preserving the source document's anchors.
---@param doc cds.Document
---@param prefix string[]
---@return cds.Document
function M.prepend(doc, prefix)
  local lines, anchors = {}, {}
  for _, line in ipairs(prefix) do
    table.insert(lines, line)
  end
  for _, line in ipairs(doc.markdown) do
    table.insert(lines, line)
  end
  for name, row in pairs(doc.anchors) do
    anchors[name] = row + #prefix
  end
  return M.new(lines, { anchors = anchors, url = doc.url })
end

---@class cds.DocumentMark: cds.LinkSpan
---@field lnum integer -- one-based rendered line
---@field col integer -- zero-based byte column, inclusive
---@field end_col integer -- zero-based byte column, exclusive
---@field hl string
---@field priority? integer
---@field link? string
---@field kind? string

---@class cds.DocumentLayout
---@field lines string[]
---@field styled? boolean
---@field blocks? integer[][]

---@class cds.RenderedDocument: cds.DocumentLayout
---@field source cds.Document
---@field lines string[]
---@field marks cds.DocumentMark[]
---@field styled boolean
---@field waiting boolean
---@field blocks? integer[][] -- { source offset, source count, rendered offset, rendered count }

--- A fresh presentation record; source and adapter results are never modified.
---@param source cds.Document
---@param lines? string[]
---@param marks? cds.DocumentMark[]
---@param waiting? boolean
---@param blocks? integer[][]
---@return cds.RenderedDocument
function M.rendered(source, lines, marks, waiting, blocks)
  return {
    source = source,
    lines = lines or source.markdown,
    marks = marks or {},
    styled = lines ~= nil,
    waiting = lines ~= nil and waiting == true,
    blocks = lines and blocks or nil,
  }
end

--- Source-position hit testing; enclosing links take precedence over images.
---@param doc cds.Document
---@param row integer
---@param col integer
---@return string?
function M.link(doc, row, col)
  return rows.select_link(doc.links, row, col)
end

--- One selection policy for source and rendered links. first selects the
--- leftmost span on the row; otherwise select the most specific cursor span.
--- An optional live line supports editable Markdown without stale metadata,
--- retaining the surrounding source document's code-fence context.
---@param source cds.Document
---@param rendered cds.RenderedDocument?
---@param row integer
---@param col integer
---@param opts? { first: boolean?, line: string? }
---@return string?
function M.target(source, rendered, row, col, opts)
  opts = opts or {}
  if rendered and rendered.styled then
    return rows.select_link(rendered.marks, row, col, opts.first)
  end
  if opts.line and opts.line ~= source.markdown[row] then
    local markdown = {}
    for i, line in ipairs(source.markdown) do
      markdown[i] = line
    end
    markdown[row] = opts.line
    return rows.select_link(M.new(markdown).links, row, col, opts.first)
  end
  return rows.select_link(source.links, row, col, opts.first)
end

--- The rendered row a source (Markdown) row lands on: its offset inside its
--- block scaled to the block's rendered height, so a block vellum doubled
--- keeps the cursor near the same text. An unstyled layout, or a row no
--- block holds, maps to itself.
---@param rendered cds.DocumentLayout
---@param row integer -- a source row, counted from one
---@return integer
function M.rendered_row(rendered, row)
  return rows.rendered_row(rendered, row)
end

--- The source row a rendered line comes from: the inverse of rendered_row.
---@param rendered cds.DocumentLayout
---@param line integer -- a rendered line, counted from one
---@return integer
function M.source_row(rendered, line)
  return rows.source_row(rendered, line)
end

--- Resolve an explicit or generated anchor and map it through vellum's blocks.
--- A compressed block lands at its first rendered line, without guessing offsets.
---@param doc cds.Document
---@param fragment string
---@param rendered? cds.DocumentLayout
---@return integer?
function M.anchor(doc, fragment, rendered)
  return rows.anchor(doc, fragment, rendered)
end

return M
