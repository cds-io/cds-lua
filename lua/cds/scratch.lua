---@tag cds.scratch
---@toc_entry Persistent scratch views
---@text
--- Own a scratch buffer and the window displaying it. Hiding retains its
--- contents; wiping it invalidates the handle and the next open recreates it.
--- A window that has switched to another buffer is no longer owned. Reopening
--- an existing view focuses it instead of creating another split.
---
--- >lua
---   local view = require("cds.scratch").new({
---     name = "[Example Results]", filetype = "markdown",
---     on_create = function(buf)
---       vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Results" })
---     end,
---   })
---   view:open({ kind = "vsplit", size = 0.5 })
---   view:toggle() -- hide; a later toggle shows the same buffer
--- <
--- Content, folds and keymaps belong to the caller's hooks. on_show is also
--- called when the buffer is displayed by native editor commands. No global
--- mappings or commands are installed by a view. destroy releases the buffer
--- and detaches windows displaying it. Other views are independent.

---@class cds.scratch
local M = {}

---@class cds.scratch.Options
---@field name string
---@field filetype string?
---@field on_create? fun(buf: integer)
---@field on_show? fun(buf: integer, win: integer)

---@class cds.scratch.Open
---@field kind? "split"|"vsplit"|"tab"|"float"
---@field size number? -- split rows/columns, or a fraction of editor dimensions
---@field float table<string, any>? -- nvim_open_win options; function values are evaluated at open

---@class cds.Scratch
---@field buf integer?
---@field win integer?
---@field opts cds.scratch.Options
---@field last cds.scratch.Open
local Scratch = {}
Scratch.__index = Scratch

--- Make an independent, lazy view. No buffer or window is created yet.
---@param opts cds.scratch.Options
---@return cds.Scratch
function M.new(opts)
  return setmetatable({ opts = opts, last = {} }, Scratch)
end

--- Get or create the owned buffer.
---@return integer
function Scratch:buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return self.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  self.buf, self.win = buf, nil
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_name(buf, self.opts.name)
    vim.bo[buf].filetype = self.opts.filetype or ""
    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = buf,
      callback = function()
        if self.buf ~= buf then
          return
        end
        local win = vim.api.nvim_get_current_win()
        self.win = win
        if self.opts.on_show then
          self.opts.on_show(buf, win)
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        if self.buf == buf then
          self.buf, self.win = nil, nil
        end
      end,
    })
    if self.opts.on_create then
      self.opts.on_create(buf)
    end
  end)
  if not ok then
    self:destroy()
    error(err)
  end
  return buf
end

--- Find a window still displaying the owned buffer.
---@return integer? win
function Scratch:window()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf, self.win = nil, nil
    return nil
  end
  if self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf then
    return self.win
  end
  self.win = vim.fn.win_findbuf(self.buf)[1]
  return self.win
end

--- Show the buffer or focus its existing window. Float dimensions are
--- evaluated on each open; split dimensions are clamped to the editor.
---@param opts? cds.scratch.Open
---@return integer win
function Scratch:open(opts)
  opts = opts or self.last
  local buf, existing = self:buffer(), self:window()
  if existing then
    vim.api.nvim_set_current_win(existing)
    return existing
  end
  local kind = opts.kind or "split"
  local win
  if kind == "float" then
    local config = { relative = "editor", width = 60, height = 20, row = 1, col = 1, border = "rounded" }
    for key, value in pairs(opts.float or {}) do
      config[key] = type(value) == "function" and value() or value
    end
    config.width = math.max(1, math.min(config.width, vim.o.columns - 4))
    config.height = math.max(1, math.min(config.height, vim.o.lines - vim.o.cmdheight - 4))
    win = vim.api.nvim_open_win(buf, true, config)
  else
    if kind == "tab" then
      vim.cmd.tabnew()
    else
      vim.cmd(kind == "vsplit" and "vsplit" or "split")
    end
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    if kind ~= "tab" and opts.size then
      local total = kind == "vsplit" and vim.o.columns or vim.o.lines
      local requested = opts.size or 1
      if requested <= 1 then
        requested = total * requested
      end
      local size = math.max(1, math.min(total - 2, math.floor(requested)))
      if kind == "vsplit" then
        vim.api.nvim_win_set_config(win, { width = size })
      else
        vim.api.nvim_win_set_config(win, { height = size })
      end
    end
  end
  self.win, self.last = win, vim.deepcopy(opts)
  return win
end

--- Hide the owned window, preserving the buffer and its text.
function Scratch:hide()
  local win = self:window()
  if win then
    -- Native :hide can hide a buffer even when its window is the last one.
    vim.api.nvim_win_call(win, function()
      if #vim.api.nvim_tabpage_list_wins(0) == 1 then
        vim.cmd("hide enew")
      else
        vim.cmd.hide()
      end
    end)
  end
  self.win = nil
end

--- Hide an open view or reopen it with the supplied/last layout.
---@param opts? cds.scratch.Open
function Scratch:toggle(opts)
  if self:window() then
    self:hide()
  else
    self:open(opts)
  end
end

--- Release the owned buffer and its associated buffer-local autocmds.
function Scratch:destroy()
  local buf = self.buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  self.buf, self.win = nil, nil
end

return require("cds.module").wrap("scratch", M)
