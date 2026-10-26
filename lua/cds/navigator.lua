---@tag cds.navigator
---@toc_entry Document tag navigation
---@text
--- new() creates independent per-window history and pending-follow guards. follow(win, target, resolve, open)
--- asks resolve(target, callback) for a destination. open(destination, error, done) calls done only when
--- navigation lands. remember records other moves; pop returns a saved buffer name and view. jump maps a document
--- anchor into a rendered buffer. forget cleans up a closed window; reset clears the session. URL fetching and
--- RFC/help tag resolution remain caller-owned.

local document = require("cds.document")
local Navigator = {}

--- An independent navigation session. Resolution and opening remain caller-owned.
---@return table
function Navigator.new()
  local M = {}
  local stacks, following = {}, {}
  --- `entry` onto the stack of `win`.
  ---@param win integer
  ---@param entry { name: string, view: vim.fn.winsaveview.ret }
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
  function M.remember(win, move)
    local buf = vim.api.nvim_win_get_buf(win)
    local entry = {
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

  --- The top of the stack of `win`, taken off; nil when it is empty.
  ---@param win integer
  ---@return { name: string, view: vim.fn.winsaveview.ret }|nil
  function M.pop(win)
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
    M.remember(win, function(done)
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
  ---@param rendered table?
  ---@param fragment string?
  ---@return boolean
  function M.jump(win, source, rendered, fragment)
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
