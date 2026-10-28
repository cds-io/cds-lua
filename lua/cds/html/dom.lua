-- Private HTML5 DOM adapter. Gumbo owns parsing and recovery; this module
-- owns the plain decoded nodes (kind, name, attrs, children, nothing of the
-- DOM's), what each tag means to the block walk of cds.html.blocks, and the
-- searches over a tree. No editor or network access.

---@class cds.html.dom
local M = {}

--- The tags whose subtrees the block walk leaves out unless told otherwise.
M.skipped = { script = true, style = true, nav = true }

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
--- The container tags that end a block without being one themselves.
M.boundaries = {}
for name in
  ("address article aside dd details div dl dt figcaption figure footer header main section summary"):gmatch("%S+")
do
  M.boundaries[name] = true
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

--- The decoded tree of `source`: a whole document, or a fragment parsed in
--- body context when `fragment` is set.
---@param source string?
---@param fragment boolean?
---@return table
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
  -- a document node always decodes; only a stray node type answers nil
  return assert(node_of(assert(dom)))
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

return M
