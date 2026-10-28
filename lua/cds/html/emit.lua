-- Private emitter for the block walk over a decoded HTML5 tree
-- (cds.html.blocks): the state one walk shares across its recursion. The
-- inline content under construction, with the formatting tags open around
-- it, which a new block or cell restarts the writer under; the anchors seen
-- since the last block, which the next block carries; the blocks emitted;
-- the tables counted. The walk's scopes (list, quote, heading) are passed
-- down the recursion and never kept here.
local spans = require("cds.html.spans")

---@class cds.html.emit
local M = {}

---@class cds.html.Emitter
---@field blocks cds.html.Block[]
---@field package pending string[]
---@field package tables integer
---@field package content table    -- the span writer of cds.html.spans
---@field package active table[]   -- the inline tags open, outermost first
---@field package fresh boolean    -- the writer was finished; the open tags go back on before more content
local Emitter = {}
Emitter.__index = Emitter

local span_tags = { a = true, strong = true, b = true, em = true, i = true, code = true }

---@param opts table   -- the options cds.html.spans.inline takes
---@return cds.html.Emitter
function M.new(opts)
  return setmetatable(
    { blocks = {}, pending = {}, tables = 0, content = spans.inline(opts), active = {}, fresh = false },
    Emitter
  )
end

-- Formatting ancestors are lexical DOM scopes: a new block or cell restarts
-- the writer under the tags still open, never guessing a missing end tag.
---@param self cds.html.Emitter
local function ensure_inline(self)
  if self.fresh then
    for _, ancestor in ipairs(self.active) do
      self.content.tag(ancestor.name, false, ancestor.attrs)
    end
    self.fresh = false
  end
end

---@param text string
function Emitter:text(text)
  ensure_inline(self)
  self.content.text(text)
end

--- Markdown written as it is, past the escapes.
---@param text string
function Emitter:put(text)
  ensure_inline(self)
  self.content.put(text)
end

---@param node table
---@param closing boolean
function Emitter:tag(node, closing)
  ensure_inline(self)
  if span_tags[node.name] and closing then
    table.remove(self.active)
  end
  self.content.tag(node.name, closing, closing and {} or node.attrs)
  if span_tags[node.name] and not closing then
    self.active[#self.active + 1] = node
  end
end

--- The inline content written so far, and a fresh start.
---@return string
function Emitter:finish()
  self.fresh = true
  return self.content.finish()
end

--- A node's id (a link's name) as an anchor the next block carries.
---@param node table
function Emitter:remember(node)
  local attrs = node.attrs or {}
  local id = attrs.id or (node.kind == "link" and attrs.name)
  if id and id ~= "" then
    self.pending[#self.pending + 1] = id
  end
end

--- `block` emitted with the pending anchors and the quote depth of `ctx`.
---@param block cds.html.Block
---@param ctx table
function Emitter:emit(block, ctx)
  block.anchors, self.pending = #self.pending > 0 and self.pending or nil, {}
  block.quote = ctx.quote > 0 and ctx.quote or nil
  self.blocks[#self.blocks + 1] = block
end

--- The inline content so far as one block of the kind `ctx` says (a
--- heading, a list item, a quote, else a paragraph); nothing when empty.
--- An item's later blocks take spaces for their marker.
---@param ctx table
function Emitter:flush(ctx)
  local text = self:finish()
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
  self:emit(block, ctx)
end

--- The next table's number, identifying the rows that belong to it.
---@return integer
function Emitter:next_table()
  self.tables = self.tables + 1
  return self.tables
end

return M
