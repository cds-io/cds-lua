---@tag cds.html
---@toc_entry HTML to Markdown
---@text
--- Convert an HTML fragment or page into a document for Markdown or vellum. document(body, { base = url, page =
--- true }) retains explicit IDs and named anchors; page selection prefers main, article, then body. Conversion is
--- pure and fetching remains caller-owned. HTML parsing requires lua-gumbo 0.5 for Lua 5.1/LuaJIT.
--- Gumbo supplies HTML5 nesting, first duplicate attributes and decoded text; Markdown policy stays in Lua.
--- Unclosed formatting and links follow the repaired DOM across block boundaries. A pre's leading newline
--- is removed only by HTML5 parsing, not again by the renderer.

local discover = require("cds.uri")
local format = require("cds.html.format")
local inline = require("cds.html.inline")
local dom = require("cds.html.dom")
local source_document = require("cds.document")
local entities = require("cds.entities")
local M = { entities = entities.entities }
local utf8 = entities.utf8

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

--- `text` as a Markdown code span: one backtick each side, or two with a
--- space inside when the text holds a backtick.
---@param text string
---@return string
function M.code(text)
  return inline.code(text)
end
--- Prose as one Markdown line: its characters escaped, and its start.
---@param text string
---@return string
function M.escape(text)
  return inline.escape(text)
end

---@class cds.html.Block
---@field anchors? string[]
---@field kind "para"|"heading"|"pre"|"quote"|"item"|"row"|"rule"
---@field text string      -- inline Markdown; a newline is a br; a pre block keeps its own
---@field level? integer   -- a heading's level, an item's list depth
---@field marker? string   -- an item's "- " or "N. "; spaces on its later blocks
---@field indent? integer  -- an item's indent: the widths of its enclosing items' markers
---@field quote? integer   -- the blockquote depth of a block inside one
---@field lang? string     -- a pre block's language, from `<code class="language-x">`
---@field cells? string[]  -- a row's cells, inline Markdown, `|` escaped
---@field header? boolean  -- a row standing as its table's header
---@field table? integer   -- identifies rows belonging to one table

---@class cds.html.Opts
---@field base? string the address relative image sources and link targets resolve against
---@field links? boolean -- preserve fragment and mail links
---@field drop? table<string, boolean> the tags dropped with their contents; an article's by default

--- The blocks of an article's HTML, in order; a block with no text is
--- dropped.
---@param html string
---@param opts? cds.html.Opts
---@return cds.html.Block[]
function M.blocks(html, opts)
  return dom.blocks(dom.parse(html, true), opts)
end

--- An article's HTML as Markdown lines: a blank line between blocks except
--- between the items of a list and the rows of a table, a blockquote's
--- lines behind `> ` per level, and never a blank at either end or two in
--- a row.
---@param html string
---@param opts? cds.html.Opts
---@return string[]
---@return table<string, integer>
function M.markdown(html, opts)
  return format.blocks(M.blocks(html, opts))
end

-- A page's chrome inside its content, dropped with its contents: an
-- article's set, the furniture a main or an article still holds, and the
-- head's title, which page() answers on its own. A header or footer there
-- is the post's own (its heading, its byline) and stays.
local chrome = {}
for name in pairs({ script = true, style = true, nav = true }) do
  chrome[name] = true
end
for name in ("aside form noscript iframe svg title template"):gmatch("%S+") do
  chrome[name] = true
end

-- The chrome of a body or a whole document, where the header and footer
-- are the site's.
local site_chrome = { header = true, footer = true }
for name in pairs(chrome) do
  site_chrome[name] = true
end

---@class cds.html.PageOpts
---@field region? "main"|"article"|"body" -- explicit content policy
---@field drop? table<string, boolean> -- override dropped elements
---@field links? boolean -- preserve fragment and mail links
---@field base? string the page's address, which relative links and images resolve against
---@field charset? string the charset the document is written in, transcoded to UTF-8 first

---@class cds.html.Page
---@field title? string the document's title, entities decoded and whitespace flattened
---@field anchors? table<string, integer>
---@field lines string[] the content region as Markdown

--- A web page's content as Markdown: the first `main` element, else the
--- first `article`, else the `body`, else the whole document, a region that
--- renders to no text giving way to the next; the region's chrome is
--- dropped (a header and footer only from a body or a whole document), and
--- its links and images resolve against the href of the document's first
--- `<base>`, itself resolved against `opts.base`, or `opts.base` when it
--- has none.
---@param document string
---@param opts? cds.html.PageOpts
---@return cds.html.Page
function M.page(document, opts)
  opts = opts or {}
  local tree = dom.parse(M.transcode(document or "", opts.charset))
  local base_node = dom.find(tree, "base")
  local href = base_node and base_node.attrs.href
  local base = opts.base
  if href and trim(href) ~= "" then
    base = base and discover.resolve(base, trim(href)) or trim(href)
  end
  local lines, anchors
  for _, name in ipairs(opts.region and { opts.region } or { "main", "article", "body" }) do
    local region = dom.find(tree, name)
    if region then
      local drop = opts.drop or ((opts.region or name == "body") and site_chrome or chrome)
      lines, anchors = format.blocks(dom.blocks(region, { base = base, links = opts.links, drop = drop }))
      if #lines > 0 then
        if region.attrs.id then
          anchors[region.attrs.id] = 1
        end
        break
      end
    end
    lines = nil
  end
  if not lines then
    lines, anchors =
      format.blocks(dom.blocks(tree, { base = base, links = opts.links, drop = opts.drop or site_chrome }))
  end
  local title_node = dom.find(tree, "title")
  local title = title_node and trim(dom.text(title_node):gsub("%s+", " "))
  return { title = title ~= "" and title or nil, lines = lines, anchors = next(anchors) and anchors or nil }
end

--- The charset a `charset=` within `s` names, lower-cased.
---@param s string
---@return string?
local function charset_in(s)
  return s:lower():match("charset%s*=%s*[\"']?([^%s;\"'/>]+)")
end

--- The charset a document is written in: the one its `Content-Type` header
--- value names, else, in its first 2048 bytes, a meta's `charset` attribute
--- or the `charset=` in the content of a meta whose `http-equiv` is
--- Content-Type, lower-cased; nil when none names one.
---@param content_type string?
---@param document string
---@return string?
function M.charset(content_type, document)
  local label = content_type and charset_in(content_type)
  if label then
    return label
  end
  local function sniff(node)
    if node.namespace and node.namespace ~= "html" then
      return nil
    end
    if node.name == "meta" then
      local attrs = node.attrs
      if attrs.charset then
        local value = attrs.charset:lower():match("^%s*([^%s;\"'/>]+)")
        if value then
          return value
        end
      elseif attrs["http-equiv"] and trim(attrs["http-equiv"]):lower() == "content-type" and attrs.content then
        local value = charset_in(attrs.content)
        if value then
          return value
        end
      end
    end
    for _, child in ipairs(node.children or {}) do
      local value = sniff(child)
      if value then
        return value
      end
    end
  end
  return sniff(dom.parse((document or ""):sub(1, 2048)))
end

-- windows-1252's 0x80 to 0x9F, by code point; the five slots it leaves
-- undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D) read as ISO-8859-1.
-- stylua: ignore
local cp1252 = {
    [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020,
    [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152,
    [0x8E] = 0x017D, [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022,
    [0x96] = 0x2013, [0x97] = 0x2014, [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A,
    [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178,
}

-- The single-byte charsets transcode() reads, by label. A page labelled
-- ISO-8859-1 is read as windows-1252, as the WHATWG Encoding Standard has
-- browsers do: such pages hold windows-1252's curly quotes in 0x80 to 0x9F,
-- where ISO-8859-1 has only control characters.
local single_byte = { ["iso-8859-1"] = true, latin1 = true, ["windows-1252"] = true, cp1252 = true }

--- Whether transcode() reads `charset` (a document in UTF-8 reads as it is).
---@param charset string
---@return boolean
function M.reads(charset)
  local label = charset:lower()
  return label == "utf-8" or label == "utf8" or single_byte[label] == true
end

--- `document` as UTF-8 when `charset` is ISO-8859-1 or windows-1252: each
--- byte above 0x7F becomes its windows-1252 code point's UTF-8. A document
--- in UTF-8 or in any other charset comes back as it was.
---@param document string
---@param charset string?
---@return string
function M.transcode(document, charset)
  if not (charset and single_byte[charset:lower()]) then
    return document
  end
  return (
    document:gsub("[\128-\255]", function(byte)
      local code = byte:byte()
      return utf8(cp1252[code] or code)
    end)
  )
end

---@class cds.html.DocumentOptions: cds.html.PageOpts
---@field page? boolean -- select document content rather than an HTML fragment

--- HTML as a shared document, preserving IDs, named anchors and link spans.
--- page=true selects main/article/body; otherwise converts an HTML fragment.
---@param body string
---@param opts? cds.html.DocumentOptions
---@return cds.Document
---@return string? title
function M.document(body, opts)
  opts = opts or {}
  if opts.page then
    local page =
      M.page(body, { base = opts.base, charset = opts.charset, links = true, region = opts.region, drop = opts.drop })
    return source_document.new(page.lines, { anchors = page.anchors, url = opts.base }), page.title
  end
  local lines, anchors = M.markdown(body, { base = opts.base, links = true, drop = opts.drop })
  return source_document.new(lines, { anchors = anchors, url = opts.base })
end

return M
