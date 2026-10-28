-- Private inline Markdown policy for decoded HTML5 content: prose escaped so
-- its Markdown characters stand as themselves, math left verbatim, code
-- spans, and a line's leading whitespace. cds.html.spans writes the inline
-- tags over it, cds.html.format the blocks; cds.html reaches the escapes
-- through it.
local M = {}

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

--- A run of spaces between two inline pieces, or nothing at all.
---@param piece string|table|nil
---@return boolean
local function blank(piece)
  return type(piece) == "string" and piece:match("^%s*$") ~= nil
end

M.blank, M.leading, M.prose, M.escaped = blank, leading, prose, inline

return M
