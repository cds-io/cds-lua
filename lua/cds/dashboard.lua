---@tag cds.dashboard
---@toc_entry Progress dashboards over a window
---@text
--- A few-line companion above an owner window showing a cds.progress
--- report: the title and elapsed time, the phases with the one running
--- marked, a bar on a phase that counts. It repaints on every change of
--- the report, once per main-loop turn, keeps the focus with the owner,
--- closes itself `linger` milliseconds after the report finishes or
--- fails, and goes with its owner window. One manager serves many
--- owners, one report each.
---
--- >lua
---   local dashboard = require("cds.dashboard").new({ filetype = "rfc-progress" })
---   dashboard:open(win, report)
--- <

---@class cds.dashboard
local M = {}

---@class cds.dashboard.Options
---@field filetype? string
---@field linger? integer   -- milliseconds the finished report stays; 1500 unless given
---@field height? integer   -- the window's rows; the report's lines, at most 8, unless given

---@class cds.Dashboard
---@field package companion cds.Companion
---@field package reports table<integer, cds.ProgressReport>   -- by owner window
---@field package offs table<integer, fun()>                    -- the subscriptions, by owner window
---@field package opts cds.dashboard.Options
---@field package opening? cds.ProgressReport                    -- the report a window is being opened for
local Dashboard = {}
Dashboard.__index = Dashboard

local MAX_HEIGHT = 8
local LINGER = 1500

---@param view cds.CompanionView
---@param report cds.ProgressReport
local function paint(view, report)
  if not (vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_buf_is_valid(view.buf)) then
    return
  end
  local lines = report:lines(vim.api.nvim_win_get_width(view.win))
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
  vim.bo[view.buf].modified = false
end

---@param opts? cds.dashboard.Options
---@return cds.Dashboard
function M.new(opts)
  opts = opts or {}
  local self = setmetatable({ reports = {}, offs = {}, opts = opts, opening = nil }, Dashboard)
  self.companion = require("cds.companion").new({
    filetype = opts.filetype,
    split = "above",
    height = function()
      local report = self.opening
      return opts.height or math.min(MAX_HEIGHT, report and (#report.phases + 1) or 2)
    end,
    window = {
      winfixheight = true,
      number = false,
      relativenumber = false,
      cursorline = false,
      wrap = false,
      signcolumn = "no",
      statuscolumn = "",
      foldcolumn = "0",
      spell = false,
    },
    accept = function(_, owner)
      return self.reports[owner] ~= nil
    end,
    on_update = function(view)
      local report = self.reports[view.owner]
      if report then
        paint(view, report)
      end
    end,
    on_create = function(view)
      vim.keymap.set("n", "q", function()
        self:close(view.owner)
      end, { buffer = view.buf, desc = "close the progress dashboard" })
      vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = view.buf,
        once = true,
        callback = function()
          self:forget(view.owner)
        end,
      })
    end,
  })
  return self
end

--- Drops the owner's report and subscription; the companion's own
--- cleanup has closed or is closing the window.
---@param owner integer
function Dashboard:forget(owner)
  local off = self.offs[owner]
  if off then
    off()
  end
  self.offs[owner], self.reports[owner] = nil, nil
end

--- Shows `report` above `owner`, focus staying with the owner, and follows
--- the report to its end.
---@param owner integer
---@param report cds.ProgressReport
---@return cds.CompanionView?
function Dashboard:open(owner, report)
  if self.reports[owner] then
    self:close(owner)
  end
  self.reports[owner] = report
  self.opening = report
  local focus = vim.api.nvim_get_current_win()
  local view = self.companion:open(owner)
  self.opening = nil
  if vim.api.nvim_win_is_valid(focus) then
    vim.api.nvim_set_current_win(focus)
  end
  if not view then
    self.reports[owner] = nil
    return nil
  end
  local pending, linger = false, self.opts.linger or LINGER
  self.offs[owner] = report:subscribe(function()
    if not pending then
      pending = true
      vim.schedule(function()
        pending = false
        if self.reports[owner] == report then
          paint(view, report)
        end
      end)
    end
    if report:finished() then
      vim.defer_fn(function()
        if self.reports[owner] == report then
          self:close(owner)
        end
      end, linger)
    end
  end)
  return view
end

--- Closes the owner's dashboard, if any.
---@param owner integer
function Dashboard:close(owner)
  self:forget(owner)
  self.companion:close(owner)
end

--- Closes every dashboard this manager opened.
function Dashboard:close_all()
  for owner in pairs(self.reports) do
    self:close(owner)
  end
  self.companion:close_all()
end

--- The owner's report while its dashboard is up.
---@param owner integer
---@return cds.ProgressReport?
function Dashboard:report(owner)
  return self.reports[owner]
end

--- The owner's dashboard window, or nil.
---@param owner integer
---@return integer?
function Dashboard:window(owner)
  local view = self.companion:get(owner)
  return view and view.win or nil
end

return require("cds.module").wrap("dashboard", M)
