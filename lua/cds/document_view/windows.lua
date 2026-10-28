-- Private window side of cds.document_view: which window shows a document
-- and how wide its text is, where each window's cursor sits in the layout
-- drawn now so a redraw can put it back, and the autocmds that ask the view
-- to draw again. Reads models and layouts only; the view's state stays in
-- cds.document_view, which hands the autocmds what to call, so this module
-- never requires it.
local document = require("cds.document")

---@class cds.document_view.windows
local M = {}

--- The window showing `buf`; the current one when none does yet, as during
--- the read of an :edit, which runs in the window the buffer is going into.
---@param buf integer
---@return integer
function M.window_of(buf)
  local win = vim.fn.bufwinid(buf)
  return win ~= -1 and win or vim.api.nvim_get_current_win()
end

--- The columns of `win` that hold text: its width less the gutter.
---@param win integer
---@return integer
function M.text_width(win)
  local info = vim.fn.getwininfo(win)[1]
  return info.width - info.textoff
end

---@class cds.document_view.HeldView
---@field win integer
---@field view table     -- the window's winsaveview
---@field row integer    -- the source row the cursor is on
---@field top integer    -- the source row at the top of the window

--- The windows showing the model's buffer with their views and the source
--- row each cursor is on in the layout drawn now, so a redraw can put it
--- back.
---@param model cds.DocumentModel
---@return cds.document_view.HeldView[]
function M.held(model)
  local held = {}
  for _, win in ipairs(vim.fn.win_findbuf(model.buf)) do
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    local layout = model.doc or { styled = false }
    held[#held + 1] = {
      win = win,
      view = view,
      row = document.source_row(layout, view.lnum),
      top = document.source_row(layout, view.topline),
    }
  end
  return held
end

--- The held views put back in the layout drawn now, each cursor on the
--- rendered row of its source row; then `views` (winsaveview tables by
--- window, the ones handed to show) applied over them, when given.
---@param model cds.DocumentModel
---@param held cds.document_view.HeldView[]
---@param views? table<integer, table>
function M.restore(model, held, views)
  for _, h in ipairs(held) do
    if vim.api.nvim_win_is_valid(h.win) and vim.api.nvim_win_get_buf(h.win) == model.buf then
      h.view.lnum = document.rendered_row(model.doc, h.row)
      h.view.topline = document.rendered_row(model.doc, h.top)
      vim.api.nvim_win_call(h.win, function()
        vim.fn.winrestview(h.view)
      end)
    end
  end
  for win, view in pairs(views or {}) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == model.buf then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
      end)
    end
  end
end

---@class cds.document_view.Handlers
---@field changed fun(event: string)   -- a resize, colorscheme, tab or window entry
---@field wiped fun()                  -- the buffer is gone

--- One augroup per document buffer, gone with the buffer: a resize, a
--- colorscheme, a tab entered or the buffer entering a window call
--- `on.changed` with the event's name, and the buffer's wipe calls
--- `on.wiped` and deletes the group.
---@param buf integer
---@param prefix string   -- the augroup's name, before the buffer number
---@param on cds.document_view.Handlers
function M.watch(buf, prefix, on)
  local group = vim.api.nvim_create_augroup(prefix .. "_" .. buf, { clear = true })
  local function changed(event)
    on.changed(event.event)
  end
  vim.api.nvim_create_autocmd({ "WinResized", "ColorScheme", "TabEnter" }, {
    group = group,
    callback = changed,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = changed,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      on.wiped()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
end

return M
