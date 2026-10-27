local window = require("cds.window")

describe("window closing", function()
  local floating
  before_each(function()
    vim.cmd("silent! only")
  end)
  after_each(function()
    if floating and vim.api.nvim_win_is_valid(floating) then
      vim.api.nvim_win_close(floating, true)
    end
    floating = nil
    vim.cmd("silent! only")
  end)

  local function float()
    floating = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 2,
    })
    return floating
  end

  it("runs the fallback for a last normal window despite an open float", function()
    local win, called = vim.api.nvim_get_current_win(), 0
    float()
    assert.is_false(window.close_or(win, function()
      called = called + 1
      assert.equals(win, vim.api.nvim_get_current_win())
    end))
    assert.equals(1, called)
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.is_true(vim.api.nvim_win_is_valid(floating))
  end)

  it("closes a normal split without running the fallback", function()
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    assert.is_true(window.close_or(win, function()
      error("unexpected fallback")
    end))
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  it("closes a float without touching the last normal window", function()
    local win = vim.api.nvim_get_current_win()
    assert.is_true(window.close_or(float(), function()
      error("unexpected fallback")
    end))
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.is_false(vim.api.nvim_win_is_valid(floating))
  end)

  it("runs a noncurrent window's fallback in that window", function()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(float())
    window.close_or(win, function()
      assert.equals(win, vim.api.nvim_get_current_win())
    end)
    assert.equals(floating, vim.api.nvim_get_current_win())
  end)
end)
