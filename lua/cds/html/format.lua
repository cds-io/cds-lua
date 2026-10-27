-- Private Markdown policy for decoded HTML5 content and flat document blocks.
local discover = require("cds.uri")
local M = {}

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

-- The inline tags written as Markdown, by the span they open.
local spans = { a = "link", strong = "strong", b = "strong", em = "em", i = "em", code = "code" }

-- The delimiters of the emphasis spans.
local delimiters = { strong = "**", em = "*" }

--- `text` as a Markdown code span: one backtick each side, or two with a
--- space inside when the text holds a backtick.
---@param text string
---@return string
function M.code(text)
  if text:find("`", 1, true) then
    return "`` " .. text .. " ``"
  end
  return "`" .. text .. "`"
end

--- Prose with its Markdown characters behind a backslash, so they stand
--- as themselves: `\`, `*`, `_`, `[`, `]`, `<`, `>`, the backtick, and `&`
--- (prose that writes `&amp;nbsp;` means the text `&nbsp;`).
---@param text string
---@return string
local function inline(text)
  return (text:gsub("[\\%*_%[%]<>`&]", "\\%0"))
end

--- The math openers and the closer each pairs with, and the Markdown fence
--- the span is written in: MathJax `\(…\)` is inline math, `\[…\]` and
--- `$$…$$` are display math.
local math_marks = {
  ["\\("] = { close = "\\)", fence = "$" },
  ["\\["] = { close = "\\]", fence = "$$" },
  ["$$"] = { close = "$$", fence = "$$" },
}

--- Prose with its math left verbatim: each MathJax span found within the
--- text, trimmed of surrounding whitespace, is written between dollars
--- (vellum's rule needs them to hug the content) and everything around it is
--- escaped by `inline`. An opener with no closer, or a span with nothing in
--- it, stays prose. Inline math followed at once by a digit gets a space
--- there, since a digit after the closing dollar makes that dollar prose.
---@param text string
---@return string
local function prose(text)
  local out, at = {}, 1
  while true do
    local from, to = text:find("\\[%(%[]", at)
    local dollars = text:find("$$", at, true)
    if dollars and (not from or dollars < from) then
      from, to = dollars, dollars + 1
    end
    if not from then
      break
    end
    local mark = math_marks[text:sub(from, to)]
    local close_from, close_to = text:find(mark.close, to + 1, true)
    local body = close_from and text:sub(to + 1, close_from - 1):match("^%s*(.-)%s*$")
    if body and body ~= "" then
      table.insert(out, inline(text:sub(at, from - 1)))
      table.insert(out, mark.fence .. body .. mark.fence)
      if mark.fence == "$" and text:sub(close_to + 1, close_to + 1):match("%d") then
        table.insert(out, " ")
      end
      at = close_to + 1
    else
      table.insert(out, inline(text:sub(at, to)))
      at = to + 1
    end
  end
  table.insert(out, inline(text:sub(at)))
  return table.concat(out)
end

--- A line of prose with a leading `#`, `>`, `-`, `+` or `N.` and a space
--- behind a backslash, so the line reads as a paragraph's.
---@param line string
---@return string
local function leading(line)
  if line:match("^[#>+-] ") then
    return "\\" .. line
  end
  local number, rest = line:match("^(%d+)(%. .*)$")
  if number then
    return number .. "\\" .. rest
  end
  return line
end

--- Prose as one Markdown line: its characters escaped, and its start.
---@param text string
---@return string
function M.escape(text)
  return leading(inline(text))
end

--- A link or image target in Markdown: angle brackets around one that holds
--- a space or a parenthesis.
---@param href string
---@return string
local function destination(href)
  if href:find("[%s()]") then
    return "<" .. href .. ">"
  end
  return href
end

--- A run of spaces between two inline pieces, or nothing at all.
---@param piece string|table|nil
---@return boolean
local function blank(piece)
  return type(piece) == "string" and piece:match("^%s*$") ~= nil
end

--- The builder's inline pieces as Markdown. A piece is Markdown as written,
--- or a closed emphasis span, `{ kind = "em"|"strong", core = string }`,
--- whose delimiters go on here: spans of one kind with only spaces between
--- them are written as one, so `*a* [*b*](u)*c*` reads `*a [b](u)c*`, which
--- Markdown parses as the one span the HTML meant.
---@param pieces (string|table)[]
---@return string
local function join(pieces)
  local out, i = {}, 1
  while i <= #pieces do
    local piece = pieces[i]
    if type(piece) == "table" then
      local cores = { piece.core }
      i = i + 1
      while true do
        local j = i
        while blank(pieces[j]) do
          j = j + 1
        end
        local after = pieces[j]
        if not (type(after) == "table" and after.kind == piece.kind) then
          break
        end
        table.insert(cores, table.concat(pieces, "", i, j - 1))
        table.insert(cores, after.core)
        i = j + 1
      end
      table.insert(out, delimiters[piece.kind] .. table.concat(cores) .. delimiters[piece.kind])
    else
      table.insert(out, piece)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- The one emphasis span a link's pieces hold, with only spaces around it;
--- nil when the link holds anything else.
---@param pieces (string|table)[]
---@return table|nil
local function sole_emphasis(pieces)
  local found
  for _, piece in ipairs(pieces) do
    if type(piece) == "table" and not found then
      found = piece
    elseif not blank(piece) then
      return nil
    end
  end
  return found
end

--- Inline content owns its pieces and spans. Span offsets index only buf;
--- finishing or discarding content always resets both together.
---@param opts cds.html.Opts
function M.inline(opts)
  local b = {}
  local buf, open = {}, {}

  --- The open inline text, collapsed, trimmed, with each br a newline and
  --- no more than one empty line in a row.
  local function text_of(pieces)
    local s = join(pieces):gsub("%s+", " ")
    s = s:gsub(" ?\1 ?", "\n"):gsub("\n\n\n+", "\n\n")
    return (s:match("^[%s]*(.-)[%s]*$"))
  end

  --- Markdown the builder writes, as it stands.
  function b.put(s)
    table.insert(buf, s)
  end

  --- Decoded HTML text, escaped outside code spans with its math kept.
  function b.text(s)
    for _, span in ipairs(open) do
      if span.kind == "code" then
        b.put(s)
        return
      end
    end
    b.put(prose(s))
  end

  --- A link's Markdown around its text `core`: `<href>` when the text is
  --- the target, the text alone for a fragment or a mailto: link.
  local function link(span, core)
    local href = span.href
    local followed = href ~= "" and (opts.links or (not href:match("^#") and not href:lower():match("^mailto:")))
    if followed and opts.base then
      href = discover.resolve(opts.base, href)
    end
    if href == core:gsub("\\(.)", "%1") then
      return "<" .. href .. ">"
    elseif followed then
      return "[" .. core .. "](" .. destination(href) .. ")"
    end
    return core
  end

  --- Closes the span at `at` and every span opened after it: each one's
  --- pieces become one piece, its Markdown around its text and the spaces
  --- at the text's ends outside the delimiters. An emphasis span stays a
  --- piece of its own for join(), and a link whose text is one emphasis
  --- span takes the emphasis outside itself, so join() can write it as
  --- one with the emphasis either side. A span with no text leaves only
  --- its spaces.
  local function close(at)
    for i = #open, at, -1 do
      local span = table.remove(open, i)
      local pieces = {}
      for j = span.from, #buf do
        table.insert(pieces, buf[j])
        buf[j] = nil
      end
      local inner = span.kind == "link" and sole_emphasis(pieces)
      local lead, core, trail = join(pieces):match("^([%s\1]*)(.-)([%s\1]*)$")
      b.put(lead)
      if core == "" then
        b.put(trail)
      elseif inner then
        b.put({ kind = inner.kind, core = link(span, inner.core) })
        b.put(trail)
      elseif span.kind == "code" then
        b.put(M.code(core) .. trail)
      elseif span.kind == "link" then
        b.put(link(span, core) .. trail)
      else
        b.put({ kind = span.kind, core = core })
        b.put(trail)
      end
    end
  end

  function b.tag(name, closing, attrs)
    local kind = spans[name]
    if kind then
      if closing then
        close(#open)
      else
        table.insert(open, { kind = kind, from = #buf + 1, href = trim(attrs.href or "") })
      end
    elseif name == "img" and not closing then
      local alt = trim(attrs.alt or ""):gsub("%s+", " ")
      local src = trim(attrs.src or "")
      if src == "" then
        b.put(inline(alt))
        return
      end
      if opts.base then
        src = discover.resolve(opts.base, src)
      end
      b.put("![" .. inline(alt) .. "](" .. destination(src) .. ")")
    end
  end

  --- Finish one cell or block and reset its Markdown formatting state.
  function b.finish()
    if #open > 0 then
      close(1)
    end
    local text = text_of(buf)
    buf, open = {}, {}
    return text
  end

  return b
end

--- A block's text as lines, one per br; a lone br ends its line with a
--- backslash (a Markdown hard break) and two make a blank between.
---@param text string
---@return string[]
local function segments(text)
  local lines = {}
  for segment in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, leading(segment))
  end
  for i = 1, #lines - 1 do
    if lines[i] ~= "" and lines[i + 1] ~= "" then
      lines[i] = lines[i] .. "\\"
    end
  end
  return lines
end

--- A code block's fence: three backticks, or one more than the longest run
--- that opens a line of the code.
---@param code string
---@return string
local function fence(code)
  local longest = 0
  for run in ("\n" .. code):gmatch("\n *(`+)") do
    longest = math.max(longest, #run)
  end
  return string.rep("`", longest >= 3 and longest + 1 or 3)
end

--- One table's rows as GFM: the header row (an empty one when the table
--- has none), the separator, the body rows.
---@param rows cds.html.Block[]
---@return string[]
---@return integer[] offsets zero-based output line for each source row
local function table_lines(rows)
  local function line(cells)
    return "| " .. table.concat(cells, " | ") .. " |"
  end
  local head = rows[1].header and rows[1].cells or nil
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row.cells)
  end
  -- The header holds a cell for every column, empty past its own.
  local header = {}
  for i = 1, width do
    header[i] = head and head[i] or ""
  end
  local lines = { line(header) }
  local rule = {}
  for i = 1, width do
    rule[i] = "---"
  end
  table.insert(lines, line(rule))
  local offsets = head and { 0 } or {}
  for i = head and 2 or 1, #rows do
    offsets[i] = #lines
    table.insert(lines, line(rows[i].cells))
  end
  return lines, offsets
end

--- One block's lines, before its blockquote prefix.
---@param block cds.html.Block
---@return string[]
local function render(block)
  if block.kind == "pre" then
    local mark = fence(block.text)
    local lines = { mark .. (block.lang or "") }
    for line in (block.text .. "\n"):gmatch("(.-)\r?\n") do
      table.insert(lines, line)
    end
    table.insert(lines, mark)
    return lines
  elseif block.kind == "rule" then
    return { "---" }
  elseif block.kind == "heading" then
    return { string.rep("#", block.level) .. " " .. leading((block.text:gsub("%s*\n%s*", " "))) }
  end
  local lines = segments(block.text)
  if block.kind == "item" then
    local indent = string.rep(" ", block.indent)
    local hang = string.rep(" ", #block.marker)
    for i, line in ipairs(lines) do
      if line ~= "" then
        lines[i] = indent .. (i == 1 and block.marker or hang) .. line
      end
    end
  end
  return lines
end

--- Render flat blocks with one Markdown and anchor policy.
---@param blocks cds.html.Block[]
---@return string[]
---@return table<string, integer>
function M.blocks(blocks)
  local out, anchors = {}, {}
  --- A line out; a blank that would stand first or follow another is
  --- dropped, except inside a code block, which keeps its own.
  local function put(line, code)
    if line == "" and not code and (#out == 0 or out[#out] == "") then
      return
    end
    table.insert(out, line)
  end
  local i, prev = 1, nil
  while i <= #blocks do
    local block = blocks[i]
    local lines, table_rows, row_offsets
    if block.kind == "row" then
      -- A run of rows is one table; a header row past its first starts the next.
      local rows, j = { block }, i + 1
      while
        blocks[j]
        and blocks[j].kind == "row"
        and not blocks[j].header
        and blocks[j].quote == block.quote
        and blocks[j].table == block.table
      do
        table.insert(rows, blocks[j])
        j = j + 1
      end
      lines, row_offsets = table_lines(rows)
      i, table_rows = j - 1, rows
    else
      lines = render(block)
    end
    local depth = block.quote or 0
    local tight = prev and prev.kind == "item" and block.kind == "item"
    if prev and not tight then
      -- The blank between two blocks of one blockquote stays inside it.
      local shared = math.min(depth, prev.quote or 0)
      put((string.rep("> ", shared):gsub("%s+$", "")))
    end
    local function record(source, offset)
      for _, id in ipairs(source.anchors or {}) do
        if anchors[id] == nil then
          anchors[id] = #out + 1 + offset
        end
      end
    end
    if table_rows then
      for row, source in ipairs(table_rows) do
        record(source, row_offsets[row])
      end
    else
      record(block, 0)
    end
    local prefix = string.rep("> ", depth)
    for _, line in ipairs(lines) do
      put(line == "" and (prefix:gsub("%s+$", "")) or (prefix .. line), block.kind == "pre")
    end
    prev, i = blocks[i], i + 1
  end
  if out[#out] == "" then
    out[#out] = nil
  end
  return out, anchors
end

return M
