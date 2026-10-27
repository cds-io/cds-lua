---@tag cds.window
---@toc_entry Window closing
---@text
--- close_or(win, fallback) closes a split or floating window. When win is the tab's last normal window,
--- run fallback in that window instead. Floats do not count as normal windows; callers own buffer policy.

local M = {}

--- Close a window when possible, or run the caller's last-window action in it.
---@param win integer
---@param fallback fun()
---@return boolean closed
function M.close_or(win, fallback)
  local normal = 0
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
    local config = vim.api.nvim_win_get_config(other)
    if config.relative == "" and not config.external then
      normal = normal + 1
    end
  end
  local config = vim.api.nvim_win_get_config(win)
  if config.relative ~= "" or config.external or normal > 1 then
    vim.api.nvim_win_close(win, false)
    return true
  end
  vim.api.nvim_win_call(win, fallback)
  return false
end

return M
