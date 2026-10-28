-- Private span writer for decoded HTML5 content: the inline tags (links,
-- emphasis, code) of a block's content written as Markdown, over the
-- escapes and math of cds.html.inline. cds.html.dom calls it for each block.
local discover = require("cds.uri")
local inline = require("cds.html.inline")
local M = {}

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

-- The inline tags written as Markdown, by the span they open.
local spans = { a = "link", strong = "strong", b = "strong", em = "em", i = "em", code = "code" }

-- The delimiters of the emphasis spans.
local delimiters = { strong = "**", em = "*" }

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
        while inline.blank(pieces[j]) do
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
    elseif not inline.blank(piece) then
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
    b.put(inline.prose(s))
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
        b.put(inline.code(core) .. trail)
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
        b.put(inline.escaped(alt))
        return
      end
      if opts.base then
        src = discover.resolve(opts.base, src)
      end
      b.put("![" .. inline.escaped(alt) .. "](" .. destination(src) .. ")")
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

return M
