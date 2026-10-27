-- Private HTML5 DOM adapter. Gumbo owns parsing/recovery; this module owns
-- plain decoded nodes and recursive block context. No editor or network access.
local format = require("cds.html.format")
local M = {}
local skipped = { script = true, style = true, nav = true }

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

local kinds = {
  p = "paragraph",
  a = "link",
  img = "image",
  em = "emphasis",
  i = "emphasis",
  strong = "strong",
  b = "strong",
  code = "code",
  br = "break",
  hr = "rule",
  ul = "list",
  ol = "list",
  li = "item",
  table = "table",
  tr = "row",
  td = "cell",
  th = "cell",
  pre = "pre",
  blockquote = "quote",
}
local boundaries = {}
for name in
  ("address article aside dd details div dl dt figcaption figure footer header main section summary"):gmatch("%S+")
do
  boundaries[name] = true
end
-- Copy to plain, serializable Lua data: no DOM objects cross this boundary.
local function node_of(node)
  if node.type == "text" or node.type == "whitespace" or node.type == "cdata" then
    return { kind = "text", text = node.data }
  end
  if node.type ~= "element" and node.type ~= "document" and node.type ~= "documentFragment" then
    return nil
  end
  local name = node.localName
  local result = {
    kind = kinds[name] or (name and name:match("^h[1-6]$") and "heading") or "container",
    name = name,
    namespace = node.namespace,
    attrs = {},
    children = {},
  }
  for _, attr in ipairs(node.attributes or {}) do
    result.attrs[attr.name] = attr.value
  end
  for _, child in ipairs(node.childNodes) do
    local converted = node_of(child)
    if converted then
      result.children[#result.children + 1] = converted
    end
  end
  return result
end

function M.parse(source, fragment)
  -- body context implements HTML fragment parsing, not full-document recovery.
  local ok, gumbo = pcall(require, "gumbo")
  if not ok then
    error(
      "cds.html requires lua-gumbo for Lua 5.1/LuaJIT; run :Lazy sync and :Lazy build lua-gumbo "
        .. "with rockspec support enabled. For manual installation, use "
        .. "`luarocks --lua-version=5.1 --local install gumbo 0.5-1` and add its tree to package.path/package.cpath.\n"
        .. tostring(gumbo),
      0
    )
  end
  local dom = gumbo.parse(source or "", fragment and { contextElement = "body" } or nil)
  return node_of(assert(dom))
end

function M.find(node, name)
  if node.name == name then
    return node
  end
  if
    node.name == "svg"
    or node.name == "math"
    or node.name == "script"
    or node.name == "style"
    or node.name == "template"
  then
    return nil
  end
  for _, child in ipairs(node.children or {}) do
    local result = M.find(child, name)
    if result then
      return result
    end
  end
end

function M.text(node)
  if node.kind == "text" then
    return node.text
  elseif node.kind == "break" then
    return "\n"
  end
  local out = {}
  for _, child in ipairs(node.children or {}) do
    out[#out + 1] = M.text(child)
  end
  return table.concat(out)
end

-- DOM nesting supplies block context. Only emission and pending IDs are shared;
-- list/quote/heading scopes are passed recursively, never reconstructed from tags.
function M.blocks(tree, opts)
  opts = opts or {}
  local blocks, pending, table_id = {}, {}, 0
  local content = format.inline(opts)
  -- Formatting ancestors are lexical DOM scopes. A new block/cell restarts
  -- the shared formatter with those scopes; it never guesses missing end tags.
  local active, fresh = {}, false
  local span_tags = { a = true, strong = true, b = true, em = true, i = true, code = true }
  local function ensure_inline()
    if fresh then
      for _, ancestor in ipairs(active) do
        content.tag(ancestor.name, false, ancestor.attrs)
      end
      fresh = false
    end
  end
  local function inline_text(text)
    ensure_inline()
    content.text(text)
  end
  local function inline_put(text)
    ensure_inline()
    content.put(text)
  end
  local function inline_tag(node, closing)
    ensure_inline()
    if span_tags[node.name] and closing then
      table.remove(active)
    end
    content.tag(node.name, closing, closing and {} or node.attrs)
    if span_tags[node.name] and not closing then
      active[#active + 1] = node
    end
  end
  local function finish()
    fresh = true
    return content.finish()
  end
  local drop = opts.drop or skipped
  local function remember(node)
    local attrs = node.attrs or {}
    local id = attrs.id or (node.kind == "link" and attrs.name)
    if id and id ~= "" then
      pending[#pending + 1] = id
    end
  end
  local function emit(block, ctx)
    block.anchors, pending = #pending > 0 and pending or nil, {}
    block.quote = ctx.quote > 0 and ctx.quote or nil
    blocks[#blocks + 1] = block
  end
  local function flush(ctx)
    local text = finish()
    if text == "" then
      return
    end
    local block = { kind = ctx.quote > 0 and "quote" or "para", text = text }
    if ctx.heading then
      block.kind, block.level = "heading", ctx.heading
    elseif ctx.item then
      block.kind, block.marker = "item", ctx.item.marker
      block.level, block.indent = ctx.depth, ctx.indent
      ctx.item.marker = string.rep(" ", #ctx.item.marker)
    end
    emit(block, ctx)
  end
  local function context(ctx, changes)
    return extend(ctx, changes)
  end
  local walk, children
  local function cell_content(node)
    if drop[node.name] then
      return
    end
    remember(node)
    if node.kind == "text" then
      inline_text(node.text)
      return
    end
    local boundary = boundaries[node.name] or node.kind == "paragraph" or node.kind == "break"
    if boundary then
      inline_put(" ")
    else
      inline_tag(node, false)
    end
    for _, child in ipairs(node.children) do
      cell_content(child)
    end
    if boundary then
      inline_put(" ")
    else
      inline_tag(node, true)
    end
  end
  local function rows_of(node, ctx, rows, id)
    if drop[node.name] then
      return
    end
    remember(node)
    if node.kind == "row" then
      local cells, th = {}, false
      for _, cell in ipairs(node.children) do
        if cell.kind == "cell" then
          cell_content(cell)
          cells[#cells + 1] = finish():gsub("\n", " "):gsub("|", "\\|")
          th = th or cell.name == "th"
        end
      end
      if table.concat(cells):find("%S") then
        local row = { kind = "row", text = table.concat(cells, " | "), cells = cells, header = false, table = id }
        emit(row, ctx)
        rows[#rows + 1] = { block = row, th = th }
      end
    else
      for _, child in ipairs(node.children or {}) do
        rows_of(child, ctx, rows, id)
      end
    end
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
      inline_text(node.text)
    elseif kind == "list" then
      flush(ctx)
      remember(node)
      local list = { ordered = node.name == "ol", n = (tonumber(node.attrs.start) or 1) - 1 }
      local inner = context(ctx, { list = list, depth = ctx.depth + 1 })
      inner.item = nil
      children(node, inner)
      flush(inner)
    elseif kind == "item" then
      flush(ctx)
      remember(node)
      local list = ctx.list or { n = 0 }
      list.n = list.n + 1
      local marker = list.ordered and (list.n .. ". ") or "- "
      local inner = context(
        ctx,
        { item = { marker = marker }, indent = ctx.child_indent or 0, child_indent = (ctx.child_indent or 0) + #marker }
      )
      children(node, inner)
      flush(inner)
    elseif kind == "quote" then
      flush(ctx)
      remember(node)
      local inner = context(ctx, { quote = ctx.quote + 1 })
      children(node, inner)
      flush(inner)
    elseif kind == "table" then
      flush(ctx)
      local rows = {}
      table_id = table_id + 1
      rows_of(node, ctx, rows, table_id)
      local has_th = false
      for _, row in ipairs(rows) do
        has_th = has_th or row.th
      end
      if rows[1] then
        rows[1].block.header = rows[1].th or not has_th
      end
    elseif kind == "pre" then
      flush(ctx)
      remember(node)
      local function pre_text(child)
        if drop[child.name] then
          return ""
        end
        remember(child)
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
      local pieces = {}
      for _, child in ipairs(node.children) do
        pieces[#pieces + 1] = pre_text(child)
      end
      -- Gumbo already applies HTML's one-leading-newline rule to pre.
      local text = table.concat(pieces):gsub("%s+$", "")
      local code = M.find(node, "code")
      local lang = code and (code.attrs.class or ""):match("language%-([%w_+#.-]+)")
      if text:find("%S") then
        emit({ kind = "pre", text = text, lang = lang }, ctx)
      end
    elseif kind == "rule" then
      flush(ctx)
      remember(node)
      emit({ kind = "rule", text = "" }, ctx)
    elseif kind == "paragraph" or kind == "heading" or boundaries[node.name] then
      flush(ctx)
      remember(node)
      local inner = kind == "heading" and context(ctx, { heading = tonumber(node.name:sub(2)) }) or ctx
      children(node, inner)
      flush(inner)
    else
      remember(node)
      if kind == "break" then
        inline_put("\1")
      else
        inline_tag(node, false)
        children(node, ctx)
        inline_tag(node, true)
      end
    end
  end
  local ctx = { quote = 0, depth = 0, indent = 0 }
  walk(tree, ctx)
  flush(ctx)
  return blocks
end

return M
