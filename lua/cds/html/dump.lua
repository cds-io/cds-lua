-- Private side of cds.html: whether a page is a flat text dump. A site that
-- publishes a PDF through a text extractor (PyMuPDF on EveryCRSReport.com)
-- hands over text runs with a <br> after each and no paragraph, list, table
-- or heading, the tables and columns already lost; the page then reads as
-- a column of cell fragments with nothing saying why. The decision is a
-- count over the text, no parse: on the pages measured, breaks make 95 to
-- 99 percent of breaks plus block elements for a dump and 22 percent at
-- most for prose, where the few breaks sit inside paragraphs; a paragraph
-- a break each is prose at 50, so the line is drawn at three quarters.
---@class cds.html.dump
local M = {}

-- A dump has at least this many breaks, and they are at least this share
-- of breaks plus block elements.
M.MIN_BREAKS = 30
M.SHARE = 0.75

M.MESSAGE = "Upstream (at source) conversion error. This page arrived as a flat run of line breaks:"
  .. " its tables, columns and figure layout were lost before it got here."

local BLOCK = {
  p = true,
  li = true,
  td = true,
  th = true,
  h1 = true,
  h2 = true,
  h3 = true,
  h4 = true,
  h5 = true,
  h6 = true,
  pre = true,
  blockquote = true,
  dd = true,
  dt = true,
}

--- The breaks in `text` and the block elements, as counts of opening tags.
---@param text string
---@return integer breaks
---@return integer blocks
function M.count(text)
  local breaks, blocks = 0, 0
  for name in text:gmatch("<(%a[%w]*)[%s/>]") do
    name = name:lower()
    if name == "br" then
      breaks = breaks + 1
    elseif BLOCK[name] then
      blocks = blocks + 1
    end
  end
  return breaks, blocks
end

--- Whether `text` is a flat text dump: MIN_BREAKS or more breaks, SHARE or
--- more of breaks plus block elements.
---@param text string
---@return boolean
function M.flattened(text)
  local breaks, blocks = M.count(text)
  return breaks >= M.MIN_BREAKS and breaks >= (breaks + blocks) * M.SHARE
end

return M
