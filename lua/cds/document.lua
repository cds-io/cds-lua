---@tag cds.document
---@toc_entry Document source contract
---@text
--- Pure Markdown documents carry one-based anchor rows and link spans with zero-based byte columns. Explicit HTML
--- anchors take precedence over generated heading slugs. Renderers preserve this source document and map its rows
--- through their block anchors. Link scanning excludes inline code and escaped delimiters; fenced code is
--- excluded from both link and heading metadata.

local M = {}

--- Whether the character at `i` of `line` is escaped by a backslash.
---@param line string
---@param i integer
---@return boolean
local function escaped(line, i)
  local slashes = 0
  while i - slashes - 1 >= 1 and line:sub(i - slashes - 1, i - slashes - 1) == "\\" do
    slashes = slashes + 1
  end
  return slashes % 2 == 1
end

--- The `[` opening the link text whose `]` is at `close`, nested brackets
--- counted and escaped ones skipped.
---@param line string
---@param close integer
---@return integer|nil
local function opening(line, close)
  local depth = 0
  for i = close - 1, 1, -1 do
    local char = line:sub(i, i)
    if not escaped(line, i) then
      if char == "]" then
        depth = depth + 1
      elseif char == "[" then
        if depth == 0 then
          return i
        end
        depth = depth - 1
      end
    end
  end
  return nil
end

--- The destination of the Markdown link or image whose `](` is at `close`,
--- and the index of its closing `)`: `<...>` when html.lua wrapped it for
--- whitespace or parentheses, the run up to `)` otherwise.
---@param line string
---@param close integer
---@return string|nil, integer|nil
local function destination(line, close)
  local from = close + 2
  if line:sub(from, from) == "<" then
    local stop = line:find(">)", from + 1, true)
    if stop then
      return line:sub(from + 1, stop - 1), stop + 1
    end
    return nil, nil
  end
  local href, stop = line:match("^([^%s()]+)%)()", from)
  if href then
    return href, stop - 1
  end
  return nil, nil
end

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

--- A heading's text as GitHub writes its anchor: lower-cased, letters,
--- digits, `-` and `_` kept, each space a dash, everything else dropped.
--- Bytes past ASCII are kept, so a heading in another script keeps its
--- letters.
---@param text string
---@return string
function M.slug(text)
  return (text:lower():gsub("[^%w%-_ \128-\255]", ""):gsub(" ", "-"))
end

--- A Markdown heading's text as it reads: links as their text, emphasis
--- and code markers and backslash escapes gone.
---@param text string
---@return string
local function plain(text)
  text = text:gsub("!?%[([^%]]*)%]%b()", "%1")
  text = text:gsub("\\(%p)", "%1"):gsub("[*`]", "")
  return text
end

--- The heading of `markdown` (a list of lines) whose slug is `fragment`:
--- its index and its text as it reads; nil when no heading has it.
---@param markdown string[]
---@param fragment string
---@return integer|nil, string|nil
function M.heading(markdown, fragment)
  local wanted = M.slug(fragment)
  for i, line in ipairs(markdown) do
    local text = line:match("^#+%s+(.-)%s*$")
    if text then
      text = plain(text)
      if M.slug(text) == wanted then
        return i, text
      end
    end
  end
  return nil, nil
end

--- Byte ranges occupied by inline code; delimiters must have matching lengths.
---@param line string
---@return integer[][]
local function code_spans(line)
  local spans, at = {}, 1
  while at <= #line do
    local first, last = line:find("`+", at)
    if not first then
      break
    end
    local stop, tail = nil, last + 1
    if not escaped(line, first) then
      while tail <= #line do
        local from, to = line:find("`+", tail)
        if not from then
          break
        end
        if to - from == last - first then
          stop = to
          break
        end
        tail = to + 1
      end
    end
    if stop then
      spans[#spans + 1] = { first, stop }
    end
    at = (stop or last) + 1
  end
  return spans
end

--- Links outside code spans, preserving byte columns and nested image links.
---@param line string
---@param row integer
---@return cds.DocumentLink[]
local function scan_links(line, row)
  local links, code = {}, code_spans(line)
  local function literal(at)
    if escaped(line, at) then
      return true
    end
    for _, span in ipairs(code) do
      if span[1] <= at and at <= span[2] then
        return true
      end
    end
    return false
  end
  local close = line:find("](", 1, true)
  while close do
    local first = not literal(close) and opening(line, close)
    local href, last = destination(line, close)
    if first and not literal(first) and href then
      local kind = first > 1 and line:sub(first - 1, first - 1) == "!" and not escaped(line, first - 1) and "image"
        or "link"
      links[#links + 1] = { lnum = row, col = first - 1, end_col = last, target = href, kind = kind }
    end
    close = line:find("](", close + 1, true)
  end
  for first, url, last in line:gmatch("()<(%a[%w+.-]*:[^%s<>]*)>()") do
    if not literal(first) then
      links[#links + 1] = { lnum = row, col = first - 1, end_col = last - 1, target = url, kind = "link" }
    end
  end
  return links
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
  local used = {}
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
      local text = line:match("^#+%s+(.-)%s*$")
      if text then
        local slug = M.slug(plain(text))
        local name, n = slug, 0
        while used[name] do
          n = n + 1
          name = slug .. "-" .. n
        end
        used[name] = true
        doc.anchors[name] = row
      end
      for _, link in ipairs(scan_links(line, row)) do
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

---@param links cds.LinkSpan[]
---@param row integer
---@param col integer
---@param first boolean?
---@return string?
local function select_link(links, row, col, first)
  local best
  for _, link in ipairs(links) do
    if (link.target or link.link) and link.lnum == row and (first or link.col <= col and col < link.end_col) then
      local earlier = best and first and link.col < best.col
      local same = best and (not first or link.col == best.col)
      local kind = link.kind or "link"
      local previous = best and (best.kind or "link")
      if
        not best
        or earlier
        or (
          same
          and (
            (previous == "image" and kind ~= "image")
            or (kind == previous and link.end_col - link.col < best.end_col - best.col)
          )
        )
      then
        best = link
      end
    end
  end
  return best and (best.target or best.link)
end

--- Source-position hit testing; enclosing links take precedence over images.
---@param doc cds.Document
---@param row integer
---@param col integer
---@return string?
function M.link(doc, row, col)
  return select_link(doc.links, row, col)
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
    return select_link(rendered.marks, row, col, opts.first)
  end
  if opts.line and opts.line ~= source.markdown[row] then
    local markdown = {}
    for i, line in ipairs(source.markdown) do
      markdown[i] = line
    end
    markdown[row] = opts.line
    return select_link(M.new(markdown).links, row, col, opts.first)
  end
  return select_link(source.links, row, col, opts.first)
end

--- Resolve an explicit or generated anchor and map it through vellum's blocks.
--- A compressed block lands at its first rendered line, without guessing offsets.
---@param doc cds.Document
---@param fragment string
---@param rendered? cds.DocumentLayout
---@return integer?
function M.anchor(doc, fragment, rendered)
  local name = fragment:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  local row = doc.anchors[name] or doc.anchors[M.slug(name)]
  if not row then
    return nil
  end
  if not rendered or not rendered.styled then
    return row
  end
  for _, block in ipairs(rendered.blocks or {}) do
    local from, count, to, rows = unpack(block)
    if from < row and row <= from + count then
      return to + 1 + (count == rows and row - 1 - from or 0)
    end
  end
  local text = plain(doc.markdown[row]:gsub("^#+%s+", ""))
  for at, line in ipairs(rendered.lines) do
    if line:find(text, 1, true) then
      return at
    end
  end
end

return M
