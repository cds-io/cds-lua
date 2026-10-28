-- Private row mapping for cds.document: which link a cursor is on, and how a
-- source row and a rendered line map onto each other through the blocks a
-- renderer anchors. Reads documents and layouts; requires cds.document.scan
-- for heading text, never cds.document.
local scan = require("cds.document.scan")

local M = {}

---@param links cds.LinkSpan[]
---@param row integer
---@param col integer
---@param first boolean?
---@return string?
function M.select_link(links, row, col, first)
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

--- The block of a layout holding row `at` on the side `side` (1 for source
--- rows, 3 for rendered rows): { source offset, source count, rendered offset, rendered count }.
---@param rendered cds.DocumentLayout
---@param side 1|3
---@param at integer
---@return integer[]?
local function block_at(rendered, side, at)
  for _, block in ipairs(rendered.blocks or {}) do
    if block[side] < at and at <= block[side] + block[side + 1] then
      return block
    end
  end
  return nil
end

--- The rendered row a source (Markdown) row lands on: its offset inside its
--- block scaled to the block's rendered height, so a block vellum doubled
--- keeps the cursor near the same text. An unstyled layout, or a row no
--- block holds, maps to itself.
---@param rendered cds.DocumentLayout
---@param row integer -- a source row, counted from one
---@return integer
function M.rendered_row(rendered, row)
  local block = rendered.styled and block_at(rendered, 1, row)
  if not block then
    return row
  end
  local from, count, to, rows = unpack(block)
  return to + 1 + math.floor((row - 1 - from) * rows / count)
end

--- The source row a rendered line comes from: the inverse of rendered_row.
---@param rendered cds.DocumentLayout
---@param line integer -- a rendered line, counted from one
---@return integer
function M.source_row(rendered, line)
  local block = rendered.styled and block_at(rendered, 3, line)
  if not block then
    return line
  end
  local from, count, to, rows = unpack(block)
  return from + 1 + math.floor((line - 1 - to) * count / rows)
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
  local row = doc.anchors[name] or doc.anchors[scan.slug(name)]
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
  local text = scan.plain(doc.markdown[row]:gsub("^#+%s+", ""))
  for at, line in ipairs(rendered.lines) do
    if line:find(text, 1, true) then
      return at
    end
  end
end

return M
