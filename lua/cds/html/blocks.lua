-- Private block walk over a decoded HTML5 tree (cds.html.dom's nodes): each
-- block-level construct as one flat cds.html.Block, in document order. The
-- DOM's nesting supplies the block context (list depth and marker, quote
-- depth, heading level), passed down the recursion as a scope and never
-- reconstructed from tags; what the walk shares across its recursion (the
-- inline content, the anchors, the blocks) is the emitter of cds.html.emit.
local dom = require("cds.html.dom")
local emit = require("cds.html.emit")

---@class cds.html.blocks
local M = {}

local function extend(a, b)
  local result = {}
  for key, value in pairs(a) do
    result[key] = value
  end
  for key, value in pairs(b) do
    result[key] = value
  end
  return result
end

--- The blocks of `tree`. `opts.drop` names the tags whose subtrees are left
--- out (script, style and nav unless given); the rest reach the span writer
--- of cds.html.spans as its options.
---@param tree table
---@param opts? table
---@return cds.html.Block[]
function M.blocks(tree, opts)
  opts = opts or {}
  local e = emit.new(opts)
  local drop = opts.drop or dom.skipped
  local walk, children
  local function cell_content(node)
    if drop[node.name] then
      return
    end
    e:remember(node)
    if node.kind == "text" then
      e:text(node.text)
      return
    end
    local boundary = dom.boundaries[node.name] or node.kind == "paragraph" or node.kind == "break"
    if boundary then
      e:put(" ")
    else
      e:tag(node, false)
    end
    for _, child in ipairs(node.children) do
      cell_content(child)
    end
    if boundary then
      e:put(" ")
    else
      e:tag(node, true)
    end
  end
  local function rows_of(node, ctx, rows, id)
    if drop[node.name] then
      return
    end
    e:remember(node)
    if node.kind == "row" then
      local cells, th = {}, false
      for _, cell in ipairs(node.children) do
        if cell.kind == "cell" then
          cell_content(cell)
          cells[#cells + 1] = e:finish():gsub("\n", " "):gsub("|", "\\|")
          th = th or cell.name == "th"
        end
      end
      if table.concat(cells):find("%S") then
        local row = { kind = "row", text = table.concat(cells, " | "), cells = cells, header = false, table = id }
        e:emit(row, ctx)
        rows[#rows + 1] = { block = row, th = th }
      end
    else
      for _, child in ipairs(node.children or {}) do
        rows_of(child, ctx, rows, id)
      end
    end
  end
  local function pre_text(child)
    if drop[child.name] then
      return ""
    end
    e:remember(child)
    if child.kind == "text" then
      return child.text
    elseif child.kind == "break" then
      return "\n"
    end
    local out = {}
    for _, nested in ipairs(child.children) do
      out[#out + 1] = pre_text(nested)
    end
    return table.concat(out)
  end
  function children(node, ctx)
    for _, child in ipairs(node.children or {}) do
      walk(child, ctx)
    end
  end
  function walk(node, ctx)
    if drop[node.name] then
      return
    end
    local kind = node.kind
    if kind == "text" then
      e:text(node.text)
    elseif kind == "list" then
      e:flush(ctx)
      e:remember(node)
      local list = { ordered = node.name == "ol", n = (tonumber(node.attrs.start) or 1) - 1 }
      local inner = extend(ctx, { list = list, depth = ctx.depth + 1 })
      inner.item = nil
      children(node, inner)
      e:flush(inner)
    elseif kind == "item" then
      e:flush(ctx)
      e:remember(node)
      local list = ctx.list or { n = 0 }
      list.n = list.n + 1
      local marker = list.ordered and (list.n .. ". ") or "- "
      local inner = extend(
        ctx,
        { item = { marker = marker }, indent = ctx.child_indent or 0, child_indent = (ctx.child_indent or 0) + #marker }
      )
      children(node, inner)
      e:flush(inner)
    elseif kind == "quote" then
      e:flush(ctx)
      e:remember(node)
      local inner = extend(ctx, { quote = ctx.quote + 1 })
      children(node, inner)
      e:flush(inner)
    elseif kind == "table" then
      e:flush(ctx)
      local rows = {}
      rows_of(node, ctx, rows, e:next_table())
      local has_th = false
      for _, row in ipairs(rows) do
        has_th = has_th or row.th
      end
      if rows[1] then
        rows[1].block.header = rows[1].th or not has_th
      end
    elseif kind == "pre" then
      e:flush(ctx)
      e:remember(node)
      local pieces = {}
      for _, child in ipairs(node.children) do
        pieces[#pieces + 1] = pre_text(child)
      end
      -- Gumbo already applies HTML's one-leading-newline rule to pre.
      local text = table.concat(pieces):gsub("%s+$", "")
      local code = dom.find(node, "code")
      local lang = code and (code.attrs.class or ""):match("language%-([%w_+#.-]+)")
      if text:find("%S") then
        e:emit({ kind = "pre", text = text, lang = lang }, ctx)
      end
    elseif kind == "rule" then
      e:flush(ctx)
      e:remember(node)
      e:emit({ kind = "rule", text = "" }, ctx)
    elseif kind == "paragraph" or kind == "heading" or dom.boundaries[node.name] then
      e:flush(ctx)
      e:remember(node)
      local inner = kind == "heading" and extend(ctx, { heading = tonumber(node.name:sub(2)) }) or ctx
      children(node, inner)
      e:flush(inner)
    else
      e:remember(node)
      if kind == "break" then
        e:put("\1")
      else
        e:tag(node, false)
        children(node, ctx)
        e:tag(node, true)
      end
    end
  end
  local ctx = { quote = 0, depth = 0, indent = 0 }
  walk(tree, ctx)
  e:flush(ctx)
  return e.blocks
end

return M
