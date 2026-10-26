---@tag cds.navigator
---@toc_entry Document tag navigation
---@text
--- new() creates independent per-window history and pending-follow guards. follow(win, target, resolve, open)
--- asks resolve(target, callback) for a destination. open(destination, error, done) calls done only when
--- navigation lands. remember records other moves; pop returns a saved buffer handle, name and view. jump maps
--- a document anchor into a rendered buffer. jump, pop and remember cancel pending follows in that window.
--- cancel(win) invalidates a follow for caller-owned navigation without discarding history. forget cleans up a
--- closed window; reset clears the session. URL fetching and RFC/help tag resolution remain caller-owned.

---@class cds.NavigationEntry
---@field buf? integer
---@field name string
---@field view vim.fn.winsaveview.ret

---@alias cds.ResolveDocument fun(target: string, done: fun(destination: any, err: any))
---@alias cds.OpenDocument fun(destination: any, err: any, done: fun())

---@class cds.Navigator
---@field cancel fun(win: integer)
---@field push fun(win: integer, entry: cds.NavigationEntry)
---@field pop fun(win: integer): cds.NavigationEntry?
---@field remember fun(win: integer, move: fun(done: fun()))
---@field forget fun(win: integer)
---@field reset fun()
---@field follow fun(win: integer, target: string, resolve: cds.ResolveDocument, open: cds.OpenDocument)
---@field jump fun(win: integer, source: cds.Document, rendered: cds.DocumentLayout?, fragment: string?): boolean

local document = require("cds.document")
local Navigator = {}

--- An independent navigation session. Resolution and opening remain caller-owned.
---@return cds.Navigator
function Navigator.new()
  local M = {}
  local stacks, following = {}, {}
  --- Invalidate a pending follow in one window without discarding its history.
  --- Call for navigation handled outside follow/jump/pop (for example an opener).
  ---@param win integer
  function M.cancel(win)
    following[win] = nil
  end

  --- `entry` onto the stack of `win`.
  ---@param win integer
  ---@param entry cds.NavigationEntry
  function M.push(win, entry)
    stacks[win] = stacks[win] or {}
    table.insert(stacks[win], entry)
  end

  --- `move` run for `win`, and where the window was (its buffer's name and
  --- its view) pushed onto its stack once the move has taken it to another
  --- buffer: checked when `move` returns, for a move done at once, and when
  --- the move calls the `done` it is handed, for one that lands later. A
  --- move that fails, or lands on the buffer it started from, pushes nothing,
  --- and a move that is both checked and done pushes once.
  ---@param win integer
  ---@param move fun(done: fun())
  local function remember(win, move)
    local buf = vim.api.nvim_win_get_buf(win)
    local entry = {
      buf = buf,
      name = vim.api.nvim_buf_get_name(buf),
      view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
    }
    local pushed = false
    local function settle()
      if not pushed and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) ~= buf then
        pushed = true
        M.push(win, entry)
      end
    end
    move(settle)
    settle()
  end

  --- Record a caller-owned move and cancel any earlier pending follow.
  ---@param win integer
  ---@param move fun(done: fun())
  function M.remember(win, move)
    M.cancel(win)
    remember(win, move)
  end

  --- The top of the stack of `win`, taken off; nil when it is empty.
  ---@param win integer
  ---@return cds.NavigationEntry?
  function M.pop(win)
    M.cancel(win)
    local stack = stacks[win]
    return stack and table.remove(stack)
  end

  --- A closed window's stack goes with it.
  ---@param win integer
  function M.forget(win)
    stacks[win] = nil
    following[win] = nil
  end

  --- Resolve and open a target in one window. A later follow replaces a pending
  --- follow there; duplicate requests join it. A callback cannot move a window
  --- that has closed or changed buffers. open calls done only after navigation lands.
  ---@param win integer
  ---@param target string
  ---@param resolve fun(target: string, done: fun(destination: any, err: any))
  ---@param open fun(destination: any, err: any, done: fun())
  function M.follow(win, target, resolve, open)
    local buf = vim.api.nvim_win_get_buf(win)
    local out = following[win]
    if out and out.target == target and out.buf == buf then
      return
    end
    local this = { target = target, buf = buf }
    following[win] = this
    remember(win, function(done)
      resolve(target, function(destination, err)
        if following[win] ~= this then
          return
        end
        following[win] = nil
        if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf) then
          return
        end
        open(destination, err, done)
      end)
    end)
  end

  --- Jump to a document anchor, recording the previous cursor in the jumplist.
  ---@param win integer
  ---@param source cds.Document
  ---@param rendered cds.DocumentLayout?
  ---@param fragment string?
  ---@return boolean
  function M.jump(win, source, rendered, fragment)
    M.cancel(win)
    local row = fragment and document.anchor(source, fragment, rendered)
    if not row then
      return false
    end
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! m'")
    end)
    vim.api.nvim_win_set_cursor(win, { row, 0 })
    return true
  end

  function M.reset()
    stacks, following = {}, {}
  end
  return M
end
return Navigator
