-- Private window side of cds.companion: the split a companion opens beside
-- its owner, the window options it applies and gives back, the autocmds that
-- follow the owner, and the teardown. Reads views only; which view an owner
-- has, and releasing or updating one, is the manager's in cds.companion,
-- which hands the autocmds those moves as handlers, so this module never
-- requires it.
---@class cds.companion.window
local M = {}

--- Puts back each window option the companion set, unless the reader
--- changed it since.
---@param view cds.CompanionView
function M.restore_options(view)
  for key, value in pairs(view.saved) do
    if vim.wo[view.win][key] == view.applied[key] then
      vim.wo[view.win][key] = value
    end
  end
end

--- Closes the companion's window while another window remains on its
--- tabpage, else leaves it showing a fresh buffer with its options put
--- back; the companion's buffer goes either way.
---@param view cds.CompanionView
function M.dispose(view)
  if vim.api.nvim_win_is_valid(view.win) then
    if vim.api.nvim_win_get_buf(view.win) == view.buf then
      local other = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(view.win))) do
        if win ~= view.win and vim.api.nvim_win_get_config(win).relative == "" then
          other = true
          break
        end
      end
      if other then
        vim.api.nvim_win_close(view.win, true)
      else
        vim.api.nvim_win_set_buf(view.win, vim.api.nvim_create_buf(true, false))
        M.restore_options(view)
      end
    else
      M.restore_options(view)
    end
  end
  if vim.api.nvim_buf_is_valid(view.buf) then
    vim.api.nvim_buf_delete(view.buf, { force = true })
  end
end

--- A scratch buffer in a split beside `owner`, focused: the buffer and its
--- window. When the window cannot open the buffer goes and the error is
--- raised again.
---@param opts cds.companion.Options
---@param owner integer
---@return integer buf
---@return integer win
function M.open(opts, owner)
  local buf = vim.api.nvim_create_buf(false, true)
  local win
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = opts.filetype or ""
    local config = { split = opts.split or "right", win = owner }
    for _, key in ipairs({ "width", "height" }) do
      local value = opts[key]
      if value then
        config[key] = type(value) == "function" and value() or value
      end
    end
    win = vim.api.nvim_open_win(buf, true, config)
  end)
  if not ok then
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    error(err)
  end
  ---@cast win integer
  return buf, win
end

--- Sets the companion's window options, remembering what each replaced.
---@param view cds.CompanionView
---@param options table<string, any>
function M.apply_options(view, options)
  for key, value in pairs(options) do
    view.saved[key] = vim.wo[view.win][key]
    view.applied[key] = value
    vim.wo[view.win][key] = value
  end
end

---@class cds.companion.Handlers
---@field live fun(): boolean        -- whether the view is still its owner's
---@field track fun()                -- the owner's cursor moved
---@field release fun()              -- the view is to go
---@field update fun(buf: integer)   -- the owner shows another buffer

--- The autocmds in the view's group that follow its owner: the cursor
--- moving in the owner tracks; the companion's window showing another
--- buffer, either window closing, or the companion's buffer wiped releases;
--- the owner showing a buffer tracks when it is the source and updates
--- otherwise. Each fires only while `on.live()` says the view still stands.
---@param view cds.CompanionView
---@param on cds.companion.Handlers
function M.watch(view, on)
  local owner, win, buf, group = view.owner, view.win, view.buf, view.group
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == owner then
        on.track()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      if not on.live() then
        return
      end
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) ~= buf then
        on.release()
      elseif vim.api.nvim_win_is_valid(owner) and vim.api.nvim_win_get_buf(owner) == args.buf then
        if args.buf == view.source_buf then
          on.track()
        else
          on.update(args.buf)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = { tostring(owner), tostring(win) },
    callback = function()
      on.release()
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      on.release()
    end,
  })
end

return M
