---@tag cds.html
---@toc_entry HTML to Markdown
---@text
--- Convert an HTML fragment or page into a document for Markdown or vellum. document(body, { base = url, page =
--- true }) retains explicit IDs and named anchors; page selection prefers main, article, then body. Conversion is
--- pure and fetching remains caller-owned.

-- An article's HTML as Markdown, for the article buffer. Article HTML is
-- rarely well-formed, so this is a tokenizer over tags and text feeding a
-- block builder, and the conversion is total: any string in, lines out. The
-- inline pieces (links, images, emphasis, code) become Markdown at the token;
-- the emitter then writes the blocks. A tag left unclosed ends at the next
-- block, and a tag this module has no rule for is dropped around its text.
-- Nothing here touches the editor.
local discover = require("cds.uri")

local source_document = require("cds.document")

local M = {}
local entities = require("cds.entities")
M.entities = entities.entities
local utf8 = entities.utf8

--- Start-tag attributes, quoted or unquoted. Ordinary tags decode entities
--- and keep the last duplicate; charset sniffing keeps the first raw value.
--- Scan boolean attributes too, so their names cannot consume the next value.
---@param s string
---@param meta? boolean
---@return table<string, string>
local function attributes(s, meta)
  local attrs, pos = {}, 1
  while true do
    local from, stop, name = s:find("([%w:%-_.]+)", pos)
    if not from then
      return attrs
    end
    pos = stop + 1
    local equal = s:match("^%s*=()%s*", pos)
    if equal then
      pos = s:find("[^%s]", equal) or (#s + 1)
      local quote = s:sub(pos, pos)
      local value
      if quote == '"' or quote == "'" then
        local close = s:find(quote, pos + 1, true)
        if not close then
          return attrs
        end
        value, pos = s:sub(pos + 1, close - 1), close + 1
      else
        value = s:match("^[^%s>]*", pos)
        pos = pos + #value
      end
      name = name:lower()
      if not meta or attrs[name] == nil then
        attrs[name] = meta and value or M.entities(value)
      end
    end
  end
end

--- The position of the `>` that ends the tag opening at `from`, quotes
--- respected (an attribute value may hold a `>`); nil when the input ends
--- first.
---@param s string
---@param from integer
---@return integer?
local function tag_end(s, from)
  local pos = from
  while true do
    local at = s:find("[>\"']", pos)
    if not at then
      return nil
    end
    local c = s:sub(at, at)
    if c == ">" then
      return at
    end
    local close = s:find(c, at + 1, true)
    if not close then
      return nil
    end
    pos = close + 1
  end
end

---@param s string
---@return string
local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

-- The elements whose content is text up to their closing tag, never markup.
local raw = { script = true, style = true, title = true }

-- The elements a self-closed start tag (`<svg/>`) ends at once; an HTML
-- element ignores the slash.
local foreign = { svg = true, math = true }

--- `name` as a pattern matching it in either case.
---@param name string
---@return string
local function anycase(name)
  return (name:gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end))
end

--- The markup the `<` at `lt` opens and the position past it, then what it
--- holds: "skip" for a comment, a doctype or a processing instruction;
--- "cdata" and the section's text; "tag" and the tag's name in lower case,
--- whether it closes, and its inside past the name; "text" for a `<` that
--- opens nothing. Nil when a tag runs past the end of the input.
---@param html string
---@param lt integer
---@return string?, integer, string?, boolean?, string?
local function token(html, lt)
  local len = #html
  local after = html:sub(lt + 1, lt + 1)
  if html:sub(lt, lt + 3) == "<!--" then
    local close = html:find("-->", lt + 4, true)
    return "skip", close and close + 3 or len + 1
  elseif html:sub(lt, lt + 8) == "<![CDATA[" then
    local close = html:find("]]>", lt + 9, true)
    return "cdata", close and close + 3 or len + 1, html:sub(lt + 9, close and close - 1 or len)
  elseif after == "!" or after == "?" then
    local close = html:find(">", lt, true)
    return "skip", close and close + 1 or len + 1
  elseif after:match("[%a/]") then
    local close = tag_end(html, lt + 1)
    if not close then
      return nil, len + 1
    end
    local slash, name, rest = html:sub(lt + 1, close - 1):match("^(/?)%s*([%a][%w-]*)(.*)$")
    if not name then
      return "skip", close + 1
    end
    return "tag", close + 1, name:lower(), slash == "/", rest
  end
  return "text", lt + 1
end

--- Whether a start tag of `name` with inside `rest` ends its element at once.
---@param name string
---@param rest string
---@return boolean
local function self_closed(name, rest)
  return foreign[name] ~= nil and rest:match("/%s*$") ~= nil
end

--- The closing tag of the `name` element whose start tag, with inside
--- `rest`, ends just before `pos`: the position of its `<`, and the
--- position past it. Elements of the same name within are counted, and a
--- raw text element within is passed over, so its text never closes
--- anything. A self-closed foreign element answers `pos` twice, and an
--- element left open runs to the end of the input.
---@param html string
---@param name string
---@param pos integer
---@param rest string
---@return integer, integer
local function end_tag(html, name, pos, rest)
  local len = #html
  if self_closed(name, rest) then
    return pos, pos
  end
  if raw[name] then
    local lt, stop = html:find("</" .. anycase(name) .. "%s*>", pos)
    if lt then
      return lt, stop + 1
    end
    return len + 1, len + 1
  end
  local depth = 1
  while true do
    local lt = html:find("<", pos, true)
    if not lt then
      break
    end
    local kind, past, tag, closes, inside = token(html, lt)
    if not kind then
      break
    end
    pos = past
    if kind == "tag" then
      tag, inside = assert(tag), inside or ""
      if tag == name and not self_closed(tag, inside) then
        depth = depth + (closes and -1 or 1)
        if depth == 0 then
          return lt, past
        end
      elseif raw[tag] and not closes then
        pos = select(2, end_tag(html, tag, past, inside))
      end
    end
  end
  return len + 1, len + 1
end

--- The document's first `name` start tag: the position past it and its
--- inside past the name; nil when there is none. Raw text and svg content
--- is passed over, so a tag written in a script or an icon's own title is
--- never the one taken.
---@param html string
---@param name string
---@return integer?, string?
local function start_tag(html, name)
  local pos = 1
  while true do
    local lt = html:find("<", pos, true)
    if not lt then
      return nil
    end
    local kind, past, tag, closes, rest = token(html, lt)
    if not kind then
      return nil
    end
    pos = past
    if kind == "tag" and not closes then
      if tag == name then
        return past, rest
      elseif raw[tag] or tag == "svg" then
        pos = select(2, end_tag(html, assert(tag), past, rest or ""))
      end
    end
  end
end

--- The content of the document's first `name` element: from past its start
--- tag to its closing tag, or to the end of the input; nil when there is
--- none.
---@param html string
---@param name string
---@return string?
---@return string? start-tag attributes
local function first(html, name)
  local past, rest = start_tag(html, name)
  if not past then
    return nil
  end
  return html:sub(past, end_tag(html, name, past, rest or "") - 1), rest
end

-- The tags that start and end a block. Everything else is inline, and an
-- inline tag with no rule below is dropped around its text.
local block_tags = {}
for name in
  ([[
    address article aside blockquote dd details div dl dt figcaption figure
    footer h1 h2 h3 h4 h5 h6 header hr li main ol p pre section summary
    table tbody tfoot thead tr ul
]]):gmatch("%S+")
do
  block_tags[name] = true
end

-- The tags of a table; inside a row only these end anything.
local table_tags = { table = true, tbody = true, thead = true, tfoot = true, tr = true, td = true, th = true }

-- The tags an article drops with their contents, to their own closing tag.
local skipped = { script = true, style = true, nav = true }

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

---@class cds.html.Opts
---@field base? string the address relative image sources and link targets resolve against
---@field links? boolean -- preserve fragment and mail links
---@field drop? table<string, boolean> the tags dropped with their contents; an article's by default

--- Inline content owns its pieces and spans. Span offsets index only buf;
--- finishing or discarding content always resets both together.
---@param opts cds.html.Opts
local function inline_builder(opts)
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
    s = M.entities(s)
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
      local at
      for i = #open, 1, -1 do
        if open[i].kind == kind then
          at = i
          break
        end
      end
      -- A second open link closes the first; emphasis may nest.
      if at and (closing or kind == "link") then
        close(at)
      end
      if not closing then
        table.insert(open, { kind = kind, from = #buf + 1, href = trim(attrs.href or "") })
      end
    elseif name == "img" then
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

  --- Finish one cell or block and start with fresh inline state. Raw mode
  --- is for preformatted text, which never opens inline spans.
  function b.finish(raw_text)
    if not raw_text and #open > 0 then
      close(1)
    end
    local text = raw_text and table.concat(buf) or text_of(buf)
    b.reset()
    return text
  end

  function b.reset()
    buf, open = {}, {}
  end

  return b
end

--- A block builder: the open text, the open inline spans, the open list
--- stack, the open table, and the modes a tag sets (a heading, a pre, a
--- table row, the blockquote depth).
---@param blocks cds.html.Block[]
---@param opts cds.html.Opts
local function builder(blocks, opts)
  local content = inline_builder(opts)
  -- Inline content belongs to the current cell when in_cell is true,
  -- otherwise to the current block.
  -- A cell requires a row; end_row closes its cell before emitting it.
  -- Flush before changing block context; anchors wait for the next emit.
  local b = {
    lists = {}, -- { ordered = boolean, n = integer }
    quote = 0,
    anchors = {},
  }

  local function emit(block)
    block.anchors = #b.anchors > 0 and b.anchors or nil
    b.anchors = {}
    if b.quote > 0 then
      block.quote = b.quote
    end
    table.insert(blocks, block)
  end

  --- Raw pre text is decoded at flush; other text goes through inline parsing.
  function b.text(text)
    if b.pre then
      content.put(text)
    else
      content.text(text)
    end
  end

  function b.flush()
    if b.pre then
      b.pre = false
      local lang = b.lang
      b.lang = nil
      local code = M.entities(content.finish(true)):gsub("^\r?\n", ""):gsub("%s+$", "")
      if code:find("%S") then
        emit({ kind = "pre", text = code, lang = lang })
      end
      return
    end
    local text = content.finish()
    local level = b.heading
    b.heading = nil
    if text == "" then
      return
    end
    if level then
      emit({ kind = "heading", text = text, level = level })
    elseif b.item then
      local indent = 0
      for i = 1, #b.lists - 1 do
        indent = indent + (b.lists[i].width or 2)
      end
      emit({ kind = "item", text = text, level = #b.lists, marker = b.item, indent = indent })
      b.item = string.rep(" ", #b.item)
    else
      emit({ kind = b.quote > 0 and "quote" or "para", text = text })
    end
  end

  --- Ends the open cell: its text, on one line, `|` escaped.
  function b.cell()
    if not b.in_cell then
      content.reset()
      return
    end
    b.in_cell = false
    local text = content.finish():gsub("\n", " "):gsub("|", "\\|")
    table.insert(b.row.cells, text)
  end

  function b.end_row()
    if b.row then
      b.cell()
      local cells, filled = b.row.cells, false
      for _, cell in ipairs(cells) do
        filled = filled or cell ~= ""
      end
      if filled then
        b.table = b.table or { th = false }
        local block = { kind = "row", text = table.concat(cells, " | "), cells = cells, header = false }
        emit(block)
        if not b.table.first then
          b.table.first, b.table.first_th = block, b.row.th
        end
        b.table.th = b.table.th or b.row.th
      end
      b.row = nil
    end
  end

  --- Ends the open table: its first row stands as the header when it holds
  --- a th cell or when no row does.
  function b.end_table()
    local t = b.table
    b.table = nil
    if t and t.first then
      t.first.header = t.first_th or not t.th
    end
  end

  local function remember_anchor(name, closing, attrs)
    if not closing then
      local id = attrs.id or (name == "a" and attrs.name)
      if id and id ~= "" then
        table.insert(b.anchors, id)
      end
    end
  end

  ---@param name string
  ---@param closing boolean
  ---@param attrs table<string, string>
  function b.tag(name, closing, attrs)
    if b.row and not table_tags[name] then
      remember_anchor(name, closing, attrs)
      -- Inside a row any other block separates words.
      if block_tags[name] or name == "br" then
        content.put(" ")
      else
        b.inline(name, closing, attrs)
      end
      return
    end
    if name == "td" or name == "th" then
      if b.row then
        b.cell()
        if not closing then
          b.in_cell = true
          b.row.th = b.row.th or name == "th"
        end
      end
      remember_anchor(name, closing, attrs)
      return
    end
    if name == "br" then
      remember_anchor(name, closing, attrs)
      content.put(b.pre and "\n" or "\1")
      return
    end
    if not block_tags[name] then
      remember_anchor(name, closing, attrs)
      b.inline(name, closing, attrs)
      return
    end
    b.end_row()
    b.flush()
    if not table_tags[name] then
      b.end_table()
    end
    remember_anchor(name, closing, attrs)
    if table_tags[name] then
      if name == "table" then
        b.end_table()
      elseif name == "tr" and not closing then
        b.row = { cells = {}, th = false }
      end
    elseif name:match("^h%d$") then
      b.heading = not closing and tonumber(name:sub(2)) or nil
    elseif name == "pre" then
      b.pre = not closing
    elseif name == "blockquote" then
      b.quote = math.max(0, b.quote + (closing and -1 or 1))
    elseif name == "ul" or name == "ol" then
      b.item = nil
      if closing then
        table.remove(b.lists)
      else
        local start = tonumber(attrs.start or "")
        table.insert(b.lists, { ordered = name == "ol", n = start and start - 1 or 0 })
      end
    elseif name == "li" then
      b.item = nil
      if not closing then
        if #b.lists == 0 then
          table.insert(b.lists, { ordered = false, n = 0 })
        end
        local list = b.lists[#b.lists]
        list.n = list.n + 1
        b.item = list.ordered and (list.n .. ". ") or "- "
        list.width = #b.item
      end
    elseif name == "hr" then
      emit({ kind = "rule", text = "" })
    end
  end

  --- Preformatted tags only supply a language; other tags are inline content.
  function b.inline(name, closing, attrs)
    if b.pre then
      if name == "code" and not closing then
        b.lang = b.lang or (attrs.class or ""):match("language%-([%w_+#.-]+)")
      end
    else
      content.tag(name, closing, attrs)
    end
  end

  return b
end

--- The blocks of an article's HTML, in order; a block with no text is
--- dropped.
---@param html string
---@param opts? cds.html.Opts
---@return cds.html.Block[]
function M.blocks(html, opts)
  html = html or ""
  opts = opts or {}
  local drop = opts.drop or skipped
  local blocks = {}
  local b = builder(blocks, opts)
  local pos, len = 1, #html
  while pos <= len do
    local lt = html:find("<", pos, true)
    if not lt then
      b.text(html:sub(pos))
      break
    end
    if lt > pos then
      b.text(html:sub(pos, lt - 1))
    end
    local kind, past, value, closes, rest = token(html, lt)
    if not kind then
      break
    end
    pos = past
    if kind == "cdata" then
      b.text((assert(value):gsub("&", "&amp;"):gsub("<", "&lt;")))
    elseif kind == "text" then
      b.text("&lt;")
    elseif kind == "tag" then
      value, rest, closes = assert(value), rest or "", closes == true
      if drop[value] and not closes then
        pos = select(2, end_tag(html, value, past, rest))
      else
        local attrs = closes and {} or attributes(rest)
        b.tag(value, closes, attrs)
      end
    end
  end
  b.end_row()
  b.flush()
  b.end_table()
  return blocks
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

--- An article's HTML as Markdown lines: a blank line between blocks except
--- between the items of a list and the rows of a table, a blockquote's
--- lines behind `> ` per level, and never a blank at either end or two in
--- a row.
---@param html string
---@param opts? cds.html.Opts
---@return string[]
---@return table<string, integer>
function M.markdown(html, opts)
  local blocks = M.blocks(html, opts)
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
      while blocks[j] and blocks[j].kind == "row" and not blocks[j].header and blocks[j].quote == block.quote do
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

-- A page's chrome inside its content, dropped with its contents: an
-- article's set, the furniture a main or an article still holds, and the
-- head's title, which page() answers on its own. A header or footer there
-- is the post's own (its heading, its byline) and stays.
local chrome = {}
for name in pairs(skipped) do
  chrome[name] = true
end
for name in ("aside form noscript iframe svg title"):gmatch("%S+") do
  chrome[name] = true
end

-- The chrome of a body or a whole document, where the header and footer
-- are the site's.
local site_chrome = { header = true, footer = true }
for name in pairs(chrome) do
  site_chrome[name] = true
end

-- Where a page's content is looked for, in order, with what each drops;
-- the whole document is the last resort.
local regions = {
  { name = "main", drop = chrome },
  { name = "article", drop = chrome },
  { name = "body", drop = site_chrome },
}

---@class cds.html.PageOpts
---@field region? "main"|"article"|"body" -- explicit content policy
---@field drop? table<string, boolean> -- override dropped elements
---@field links? boolean -- preserve fragment and mail links
---@field base? string the page's address, which relative links and images resolve against
---@field charset? string the charset the document is written in, transcoded to UTF-8 first

---@class cds.html.Page
---@field title? string the document's title, entities decoded and whitespace flattened
---@field anchors table<string, integer>
---@field lines string[] the content region as Markdown

--- A web page's content as Markdown: the first `main` element, else the
--- first `article`, else the `body`, else the whole document, a region that
--- renders to no text giving way to the next; the region's chrome is
--- dropped (a header and footer only from a body or a whole document), and
--- its links and images resolve against the href of the document's first
--- `<base>`, itself resolved against `opts.base`, or `opts.base` when it
--- has none.
---@param document string
---@param opts cds.html.PageOpts
---@return cds.html.Page
function M.page(document, opts)
  document = document or ""
  if opts.charset then
    document = M.transcode(document, opts.charset)
  end
  local base = opts.base
  local _, inside = start_tag(document, "base")
  local href = inside and attributes(inside).href
  if href and trim(href) ~= "" then
    href = trim(href)
    base = base and discover.resolve(base, href) or href
  end
  local lines, anchors
  local selected = opts.region and { { name = opts.region, drop = opts.drop or site_chrome } } or regions
  for _, region in ipairs(selected) do
    local content, rest = first(document, region.name)
    if content then
      lines, anchors = M.markdown(content, { base = base, drop = opts.drop or region.drop, links = opts.links })
    end
    if lines and #lines > 0 then
      local id = rest and attributes(rest).id
      if id then
        anchors[id] = 1
      end
      break
    end
    lines = nil
  end
  local title = first(document, "title")
  title = title and trim((M.entities(title):gsub("%s+", " ")))
  if not lines then
    lines, anchors = M.markdown(document, { base = base, drop = opts.drop or site_chrome, links = opts.links })
  end
  return { title = title ~= "" and title or nil, lines = lines, anchors = next(anchors or {}) and anchors or nil }
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
  for tag in (document or ""):sub(1, 2048):gmatch("<[Mm][Ee][Tt][Aa][%s/][^>]*>") do
    local attrs = attributes(tag:sub(6), true)
    if attrs.charset then
      label = attrs.charset:lower():match("^%s*([^%s;\"'/>]+)")
    elseif attrs["http-equiv"] and trim(attrs["http-equiv"]):lower() == "content-type" and attrs.content then
      label = charset_in(attrs.content)
    end
    if label then
      return label
    end
  end
  return nil
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
