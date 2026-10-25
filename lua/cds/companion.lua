---@tag cds.companion
---@toc_entry Window-owned companion views
---@text
--- Attach a sidebar to an editor window. Each owner gets its own scratch
--- buffer and split, even when two owners show the same document. The manager
--- tracks buffer changes and cursor movement, forgets a view when either
--- window closes, and releases its buffer and autocmds. Window-close cleanup
--- is deferred so it cannot interrupt the :q that triggered it.
---
--- The caller supplies meaning through accept, on_update and on_track:
--- >lua
---   local contents = require("cds.companion").new({
---     filetype = "example-contents", width = 32,
---     accept = function(buf) return vim.bo[buf].filetype == "help" end,
---     on_update = function(view, buf)
---       vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, {
---         "Contents of " .. vim.api.nvim_buf_get_name(buf),
---       })
---     end,
---   })
---   contents:open(vim.api.nvim_get_current_win())
--- <
--- accept answers true for a supported buffer, false to close, or nil to
--- check again on the next main-loop turn (a buffer still being initialized).
--- A deferred answer is applied only to the same view and owner buffer.
--- refresh redraws after the owner's content changes; track follows its
--- cursor, except while the reader is in the companion. Hooks own content,
--- mappings and navigation; data is an independent table for each view.
---
--- Closing the last normal window of a tab leaves an empty buffer instead;
--- floating windows do not count as replacements. Options set through window
--- are restored when a window survives cleanup. A companion window switched
--- to an unrelated buffer is detached and never closed by later cleanup.

---@class cds.companion
local M = {}
local sequence = 0

---@class cds.CompanionView
---@field owner integer
---@field source_buf integer
---@field buf integer
---@field win integer
---@field data table<string, any>
---@field package group integer
---@field package saved table<string, any>
---@field package applied table<string, any>

---@class cds.companion.Options
---@field filetype string?
---@field split? "left"|"right"|"above"|"below"
---@field width? integer|fun(): integer
---@field height? integer|fun(): integer
---@field window? table<string, any> -- window-local options owned by the companion
---@field accept? fun(buf: integer, owner: integer): boolean?
---@field on_create? fun(view: cds.CompanionView)
---@field on_update? fun(view: cds.CompanionView, buf: integer)
---@field on_track? fun(view: cds.CompanionView)

---@class cds.Companion
---@field package opts cds.companion.Options
---@field package views table<integer, cds.CompanionView>
---@field package id integer
local Companion = {}
Companion.__index = Companion

---@param view cds.CompanionView
local function restore_options(view)
  for key, value in pairs(view.saved) do
    -- Preserve an option the reader changed after the companion set it.
    if vim.wo[view.win][key] == view.applied[key] then
      vim.wo[view.win][key] = value
    end
  end
end

---@param view cds.CompanionView
local function dispose(view)
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
        restore_options(view)
      end
    else
      restore_options(view)
    end
  end
  if vim.api.nvim_buf_is_valid(view.buf) then
    vim.api.nvim_buf_delete(view.buf, { force = true })
  end
end

--- Make an independent set of companions. No windows are opened yet.
---@param opts cds.companion.Options
---@return cds.Companion
function M.new(opts)
  sequence = sequence + 1
  return setmetatable({ opts = opts, views = {}, id = sequence }, Companion)
end

---@param self cds.Companion
---@param owner integer
---@param view cds.CompanionView
---@param deferred? boolean
local function release(self, owner, view, deferred)
  if self.views[owner] ~= view then
    return
  end
  self.views[owner] = nil
  vim.api.nvim_del_augroup_by_id(view.group)
  if deferred then
    vim.schedule(function()
      dispose(view)
    end)
  else
    dispose(view)
  end
end

--- Return a live view; stale handles are forgotten before deferred cleanup.
---@param owner integer
---@return cds.CompanionView?
function Companion:get(owner)
  local view = self.views[owner]
  if
    view
    and (
      not vim.api.nvim_win_is_valid(owner)
      or not vim.api.nvim_win_is_valid(view.win)
      or vim.api.nvim_win_get_buf(view.win) ~= view.buf
    )
  then
    release(self, owner, view, true)
    return nil
  end
  return view
end

--- Close a companion without closing its owner.
---@param owner integer
function Companion:close(owner)
  local view = self.views[owner]
  if view then
    release(self, owner, view)
  end
end

--- Notify the caller that the owner's cursor moved; leave the companion's
--- selection alone while it has focus.
---@param owner integer
function Companion:track(owner)
  local view = self:get(owner)
  if view and vim.api.nvim_get_current_win() ~= view.win and self.opts.on_track then
    self.opts.on_track(view)
  end
end

---@param self cds.Companion
---@param view cds.CompanionView
---@param buf integer
---@param retried? boolean
local function update(self, view, buf, retried)
  if
    self.views[view.owner] ~= view
    or not vim.api.nvim_win_is_valid(view.owner)
    or vim.api.nvim_win_get_buf(view.owner) ~= buf
  then
    return
  end
  ---@type boolean?
  local accepted = true
  if self.opts.accept then
    accepted = self.opts.accept(buf, view.owner)
  end
  if accepted == nil and not retried then
    vim.schedule(function()
      update(self, view, buf, true)
    end)
  elseif accepted then
    view.source_buf = buf
    if self.opts.on_update then
      self.opts.on_update(view, buf)
    end
  else
    self:close(view.owner)
  end
end

--- Rebuild a companion from its owner's current buffer, with the same
--- acceptance and deferred-initialization checks as a buffer change.
---@param owner integer
function Companion:refresh(owner)
  local view = self:get(owner)
  if view then
    update(self, view, vim.api.nvim_win_get_buf(owner))
  end
end

--- Open beside the owner and focus the companion. Unsupported or unfinished
--- initial buffers open nothing; opening an existing view returns it unchanged.
---@param owner integer
---@return cds.CompanionView?
function Companion:open(owner)
  local existing = self:get(owner)
  if existing then
    return existing
  end
  if not vim.api.nvim_win_is_valid(owner) then
    return nil
  end
  local source = vim.api.nvim_win_get_buf(owner)
  if self.opts.accept and self.opts.accept(source, owner) ~= true then
    return nil
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local win
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = self.opts.filetype or ""
    local config = { split = self.opts.split or "right", win = owner }
    for _, key in ipairs({ "width", "height" }) do
      local value = self.opts[key]
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
  local group = vim.api.nvim_create_augroup("CdsCompanion" .. self.id .. "_" .. owner, { clear = true })
  ---@type cds.CompanionView
  local view =
    { owner = owner, source_buf = source, buf = buf, win = win, group = group, data = {}, saved = {}, applied = {} }
  self.views[owner] = view
  local initialized, failure = pcall(function()
    for key, value in pairs(self.opts.window or {}) do
      view.saved[key] = vim.wo[win][key]
      view.applied[key] = value
      vim.wo[win][key] = value
    end
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      callback = function()
        if vim.api.nvim_get_current_win() == owner then
          self:track(owner)
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function(args)
        if self.views[owner] ~= view then
          return
        end
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) ~= buf then
          release(self, owner, view, true)
        elseif vim.api.nvim_win_is_valid(owner) and vim.api.nvim_win_get_buf(owner) == args.buf then
          if args.buf == view.source_buf then
            self:track(owner)
          else
            update(self, view, args.buf)
          end
        end
      end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = group,
      pattern = { tostring(owner), tostring(win) },
      callback = function()
        release(self, owner, view, true)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buf,
      callback = function()
        release(self, owner, view, true)
      end,
    })
    if self.opts.on_create then
      self.opts.on_create(view)
    end
    if self.opts.on_update then
      self.opts.on_update(view, source)
    end
  end)
  if not initialized then
    release(self, owner, view)
    error(failure)
  end
  return view
end

--- Toggle a companion without changing other owners' views.
---@param owner integer
function Companion:toggle(owner)
  if self:get(owner) then
    self:close(owner)
  else
    self:open(owner)
  end
end

--- Close every view owned by this manager.
function Companion:close_all()
  for owner in pairs(self.views) do
    self:close(owner)
  end
end

return require("cds.module").wrap("companion", M)
