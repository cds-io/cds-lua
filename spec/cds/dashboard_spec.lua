local progress = require("cds.progress")
local dashboards = require("cds.dashboard")

describe("cds.dashboard", function()
  local owner, buf, clock, report, dashboard

  before_each(function()
    vim.cmd("tabnew")
    owner = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(owner, buf)
    clock = 1000
    report = progress.new({
      title = "CRS reports by topic",
      plan = { "reading source", "styling" },
      now = function()
        return clock
      end,
    })
    dashboard = dashboards.new({ filetype = "test-progress", linger = 20 })
  end)

  after_each(function()
    dashboard:close_all()
    vim.cmd("tabclose")
  end)

  local function window()
    return dashboard:window(owner)
  end

  it("opens above the owner, leaves the focus with the owner, and shows the report", function()
    dashboard:open(owner, report)
    local win = window()
    assert.is_number(win)
    assert.equals(owner, vim.api.nvim_get_current_win())
    assert.equals("test-progress", vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
    assert.is_true(vim.api.nvim_win_get_position(win)[1] < vim.api.nvim_win_get_position(owner)[1])
    assert.equals(3, vim.api.nvim_win_get_height(win))
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    assert.matches("^CRS reports by topic", lines[1])
    assert.equals("· reading source", lines[2])
    assert.equals(report, dashboard:report(owner))
  end)

  it("repaints on a change, once per tick", function()
    dashboard:open(owner, report)
    local win = window()
    report:begin("reading source", 32)
    report:tick(8)
    assert.is_true(vim.wait(200, function()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      return lines[2] == "▸ reading source [████░░░░░░░░░░░░] 8/32"
    end))
  end)

  it("closes itself a beat after the report finishes", function()
    dashboard:open(owner, report)
    local win = window()
    report:begin("styling")
    clock = 2500
    report:finish()
    assert.is_true(vim.wait(500, function()
      return not vim.api.nvim_win_is_valid(win)
    end))
    assert.is_nil(dashboard:report(owner))
    assert.equals(owner, vim.api.nvim_get_current_win())
  end)

  it("goes with its owner window", function()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(owner)
    dashboard:open(owner, report)
    local win = window()
    vim.api.nvim_win_close(owner, true)
    assert.is_true(vim.wait(500, function()
      return not vim.api.nvim_win_is_valid(win)
    end))
    assert.is_nil(dashboard:report(owner))
    owner = other
  end)
end)
