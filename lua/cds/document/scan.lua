-- Private Markdown scanner for cds.document: the link and heading metadata
-- a source document is built from. Links are found outside inline code and
-- escaped delimiters, with their byte columns kept; headings read as text
-- and slug. Pure functions over lines; cds.document and cds.document.rows
-- require this, it requires nothing.
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

--- Allocate unique names in input order without modifying the bases. Callers
--- supply their own slugs/prefixes and the first duplicate suffix (default 1).
---@param bases string[]
---@param first? integer
---@return string[]
function M.unique_names(bases, first)
  local names, used = {}, {}
  for i, base in ipairs(bases) do
    local name, suffix = base, first or 1
    while used[name] do
      name = base .. "-" .. suffix
      suffix = suffix + 1
    end
    used[name], names[i] = true, name
  end
  return names
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
function M.plain(text)
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
      text = M.plain(text)
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

--- Inline code can span soft line breaks, but not separate block paragraphs.
--- Project paragraph byte ranges back onto their original source rows.
---@param markdown string[]
---@param eligible table<integer, boolean>
---@return table<integer, integer[][]>
function M.paragraph_code(markdown, eligible)
  local found, lines, rows = {}, {}, {}
  local function flush()
    local spans, offset = code_spans(table.concat(lines, "\n")), 0
    for i, line in ipairs(lines) do
      local ranges = {}
      for _, span in ipairs(spans) do
        local from, to = math.max(1, span[1] - offset), math.min(#line, span[2] - offset)
        if from <= to then
          ranges[#ranges + 1] = { from, to }
        end
      end
      found[rows[i]] = ranges
      offset = offset + #line + 1
    end
    lines, rows = {}, {}
  end
  for row, line in ipairs(markdown) do
    if not eligible[row] or line:match("^%s*$") then
      flush()
    else
      local heading = line:match("^#+%s+")
      if heading then
        flush()
      end
      lines[#lines + 1], rows[#rows + 1] = line, row
      if heading then
        flush()
      end
    end
  end
  flush()
  return found
end

--- Links outside code spans, preserving byte columns and nested image links.
---@param line string
---@param row integer
---@param code integer[][]
---@return cds.DocumentLink[]
function M.scan_links(line, row, code)
  local links = {}
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

return M
