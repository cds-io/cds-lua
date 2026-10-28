-- Private Markdown policy for flat document blocks: each block of
-- cds.html.dom as its Markdown lines, with the anchors it carries. The
-- inline policy (escapes, math, spans) is cds.html.inline.
local inline = require("cds.html.inline")
local M = {}

--- A block's text as lines, one per br; a lone br ends its line with a
--- backslash (a Markdown hard break) and two make a blank between.
---@param text string
---@return string[]
local function segments(text)
  local lines = {}
  for segment in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, inline.leading(segment))
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
    return { string.rep("#", block.level) .. " " .. inline.leading((block.text:gsub("%s*\n%s*", " "))) }
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
