---@tag cds.redraw
---@toc_entry Preserving selection on refresh
---@text
--- Refreshing a listing can move the item under the cursor. Save its stable
--- identity before replacing the lines, then find that identity in the new
--- listing. redraw does this for every window showing the buffer, so splits
--- can preserve different selections. If an item disappears, it restores the
--- old cursor position with the line clamped to the new buffer length.
---
--- Keep the selected item after sorting ~
--- This complete example opens a scratch listing with "Beta" selected, then
--- sorts it. The cursor follows Beta from line 1 to line 2: >lua
---
---   local redraw = require("cds.redraw")
---   local buf = vim.api.nvim_create_buf(false, true)
---   vim.api.nvim_set_current_buf(buf)
---   local items = { { id = "b", label = "Beta" }, { id = "a", label = "Alpha" } }
---   local function draw()
---     local lines = {}
---     for i, item in ipairs(items) do lines[i] = item.label end
---     vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
---   end
---   draw()
---   vim.api.nvim_win_set_cursor(0, { 1, 0 })
---   local keep = {
---     key = function(win)
---       local item = items[vim.api.nvim_win_get_cursor(win)[1]]
---       return item and item.id
---     end,
---     seek = function(win, id)
---       for row, item in ipairs(items) do
---         if item.id == id then
---           vim.api.nvim_win_set_cursor(win, { row, 0 })
---           return true
---         end
---       end
---       return false
---     end,
---   }
---   redraw.windows(buf, function()
---     table.sort(items, function(a, b) return a.label < b.label end)
---     draw()
---   end, keep)
---   assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
--- <
--- Change items inside the draw callback: key must still see the old listing
--- when windows captures the selection. seek moves the cursor itself and
--- returns true when it finds the key. Omit keep to preserve line positions.
---
--- For text that arrives later, call places(buf, keep) before changing the
--- model, then restore(saved, keep) once the new text is present. windows wraps
--- those two calls around a synchronous draw. It returns the affected windows
--- so the caller can refresh related folds or sidebars.
---@class cds.redraw

local M = {}

---@class cds.redraw.Keep
---@field key fun(win: integer): any                 -- the window's place before the draw; nil for none
---@field seek fun(win: integer, key: any): boolean  -- the window onto its place after; false when the place is gone

--- Sets the window's cursor, its line clamped to the buffer's length.
---@param win integer
---@param cursor integer[]
local function clamp(win, cursor)
  local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], last), cursor[2] })
end

---@class cds.redraw.Places
---@field buf integer
---@field wins integer[]                                    -- the windows showing the buffer when taken
---@field of table<integer, { cursor: integer[], key: any }>  -- each window's cursor and place

--- Takes the windows showing `buf` and each one's place before a draw: its
--- cursor, and the key `keep` names when given.
---@param buf integer
---@param keep? cds.redraw.Keep
---@return cds.redraw.Places
function M.places(buf, keep)
  local wins = vim.fn.win_findbuf(buf)
  local of = {}
  for _, win in ipairs(wins) do
    of[win] = { cursor = vim.api.nvim_win_get_cursor(win), key = keep and keep.key(win) or nil }
  end
  return { buf = buf, wins = wins, of = of }
end

--- Restores each window after the new text is available. Uses keep.seek to
--- find its saved key, or restores the old cursor with its line clamped to
--- the buffer length. Skips windows that closed or switched buffers.
---@param places cds.redraw.Places
---@param keep? cds.redraw.Keep
function M.restore(places, keep)
  for _, win in ipairs(places.wins) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == places.buf then
      local place = places.of[win]
      local found = keep ~= nil and place.key ~= nil and keep.seek(win, place.key)
      if not found then
        clamp(win, place.cursor)
      end
    end
  end
end

--- Captures cursor positions and keys, calls draw with the windows showing
--- buf, then restores their selections. draw must update the text before it
--- returns. Returns the windows for related fold or sidebar updates.
---@param buf integer
---@param draw fun(wins: integer[])
---@param keep? cds.redraw.Keep
---@return integer[] wins
function M.windows(buf, draw, keep)
  local places = M.places(buf, keep)
  draw(places.wins)
  M.restore(places, keep)
  return places.wins
end

return require("cds.module").wrap("redraw", M)
