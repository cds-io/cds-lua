---@tag cds.pick
---@toc_entry Keyed floating selection
---@text
--- Select from a short list without putting window ownership, mappings and
--- teardown in each plugin. The caller supplies items and their presentation;
--- pick owns the temporary buffer and settles exactly once, including when
--- the user leaves or closes the window. The callback runs on the next main
--- loop turn, after teardown. Cancellation answers nil.
---
--- >lua
---   require("cds.pick").select({ "Local", "Mainnet" }, {
---     title = " Network ",
---   }, function(item)
---     if item then vim.notify("Selected " .. item) end
---   end)
--- <
--- format_item renders an item; selectable can mark a heading as unselectable.
--- A single selectable item settles without opening a window. With more than
--- 26 items all keys have the same length, so no key shadows another's prefix.
--- Escape and Ctrl-C cancel. Leaving the picker cancels without stealing focus.

---@class cds.pick
local M = {}
local ALPHABET = "asdfjkl;ghqwertyuiopzxcvbnm"
local ns = vim.api.nvim_create_namespace("cds.pick")

---@class cds.pick.Options
---@field title string?
---@field format_item? fun(item: any): string
---@field selectable? fun(item: any): boolean
---@field highlight string? -- key highlight group; defaults to Special

---@class cds.pick.Handle
---@field buf integer
---@field win integer
---@field close fun() -- cancel and restore the originating view, once

--- Generate prefix-free selection keys in home-row-first order.
---@param count integer
---@return string[]
function M.keys(count)
  local width, capacity = 1, #ALPHABET
  while capacity < count do
    width, capacity = width + 1, capacity * #ALPHABET
  end
  local keys = {}
  for i = 1, count do
    local value, chars = i - 1, {}
    for pos = width, 1, -1 do
      local digit = value % #ALPHABET + 1
      chars[pos] = ALPHABET:sub(digit, digit)
      value = math.floor(value / #ALPHABET)
    end
    keys[i] = table.concat(chars)
  end
  return keys
end

--- Show items in a temporary centered float. Returns its handles when a
--- window is opened; empty or singleton selections only schedule the callback.
---@param items any[]
---@param opts cds.pick.Options
---@param callback fun(item: any?)
---@return cds.pick.Handle?
function M.select(items, opts, callback)
  local choices, rows = {}, {}
  local format_item = opts.format_item or tostring
  for _, item in ipairs(items) do
    local selectable = not opts.selectable or opts.selectable(item)
    rows[#rows + 1] = { text = format_item(item), choice = selectable and (#choices + 1) or nil }
    if selectable then
      choices[#choices + 1] = item
    end
  end
  if #choices <= 1 then
    vim.schedule(function()
      callback(choices[1])
    end)
    return nil
  end

  local keys, lines, width = M.keys(#choices), {}, 1
  for _, row in ipairs(rows) do
    local key = row.choice and keys[row.choice]
    local line = key and ("[%s] %s"):format(key, row.text) or ("    " .. row.text)
    lines[#lines + 1] = line
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Press key to select, <Esc> to cancel"
  width = math.max(width, vim.fn.strdisplaywidth(lines[#lines]))

  local origin = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_win_get_buf(origin)
  local view = vim.fn.winsaveview()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  width = math.max(1, math.min(width + 2, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - vim.o.cmdheight - 4))
  local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal",
    border = "rounded",
    title = opts.title or " Select ",
    title_pos = "center",
  })
  if not ok then
    vim.api.nvim_buf_delete(buf, { force = true })
    error(win)
  end
  vim.wo[win].wrap = false
  for i, row in ipairs(rows) do
    if row.choice then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, {
        end_col = 1 + #keys[row.choice],
        hl_group = opts.highlight or "Special",
      })
    end
  end

  local settled = false
  local group = vim.api.nvim_create_augroup("CdsPick" .. buf, { clear = true })
  local function finish(item, restore)
    if settled then
      return
    end
    settled = true
    vim.api.nvim_del_augroup_by_id(group)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    if restore and vim.api.nvim_win_is_valid(origin) and vim.api.nvim_win_get_buf(origin) == origin_buf then
      vim.api.nvim_set_current_win(origin)
      vim.fn.winrestview(view)
    end
    vim.schedule(function()
      callback(item)
    end)
  end
  for i, key in ipairs(keys) do
    vim.keymap.set("n", key, function()
      finish(choices[i], true)
    end, { buffer = buf, nowait = true })
  end
  local function cancel()
    finish(nil, true)
  end
  for _, key in ipairs({ "<Esc>", "<C-c>" }) do
    vim.keymap.set("n", key, cancel, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        finish(nil, false)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      vim.schedule(function()
        finish(nil, false)
      end)
    end,
  })
  return { buf = buf, win = win, close = cancel }
end

return require("cds.module").wrap("pick", M)
