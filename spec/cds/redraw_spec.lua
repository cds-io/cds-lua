local redraw = require("cds.redraw")

describe("cds.redraw", function()
  local buf, left, right

  local function lines(...)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ... })
  end

  before_each(function()
    vim.cmd("silent only!")
    buf = vim.api.nvim_create_buf(false, true)
    lines("one", "two", "three", "four")
    left = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(left, buf)
    vim.cmd("vsplit")
    right = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(right, buf)
    vim.api.nvim_win_set_cursor(left, { 2, 0 })
    vim.api.nvim_win_set_cursor(right, { 4, 0 })
  end)

  after_each(function()
    vim.cmd("silent only!")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("draws once, with the windows showing the buffer, and answers them", function()
    local drawn = {}
    local wins = redraw.windows(buf, function(w)
      table.insert(drawn, w)
    end)
    assert.are.equal(1, #drawn)
    table.sort(drawn[1])
    table.sort(wins)
    assert.are.same({ left, right }, wins)
    assert.are.same(wins, drawn[1])
  end)

  it("keeps each window on its line, clamped to the new length, with no key", function()
    redraw.windows(buf, function()
      lines("one", "two", "three")
    end)
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(left))
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(right))
  end)

  it("seeks each window to the place its key names, and keeps the line where the key is gone", function()
    local keep = {
      key = function(win)
        local row = vim.api.nvim_win_get_cursor(win)[1]
        return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      end,
      seek = function(win, text)
        for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line == text then
            vim.api.nvim_win_set_cursor(win, { i, 0 })
            return true
          end
        end
        return false
      end,
    }
    -- "two" moves to the top; "four" is gone
    redraw.windows(buf, function()
      lines("two", "one", "three")
    end, keep)
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(left))
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(right))
  end)

  it("takes a nil key as no place to seek", function()
    local sought = false
    redraw.windows(buf, function()
      lines("a", "b")
    end, {
      key = function()
        return nil
      end,
      seek = function()
        sought = true
        return true
      end,
    })
    assert.is_false(sought)
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(left))
  end)

  it("takes the places before and restores them whenever after, as two halves", function()
    local keep = {
      key = function(win)
        local row = vim.api.nvim_win_get_cursor(win)[1]
        return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      end,
      seek = function(win, text)
        for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line == text then
            vim.api.nvim_win_set_cursor(win, { i, 0 })
            return true
          end
        end
        return false
      end,
    }
    local places = redraw.places(buf, keep)
    assert.are.same({ cursor = { 2, 0 }, key = "two" }, places.of[left])
    -- the skeleton first, the text later
    lines("")
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(left))
    lines("header", "four", "two")
    redraw.restore(places, keep)
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(left))
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(right))
  end)

  it("passes over a window that moved to another buffer before the restore", function()
    local places = redraw.places(buf)
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(right, other)
    lines("one")
    redraw.restore(places)
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(left))
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(right))
    assert.are.equal(other, vim.api.nvim_win_get_buf(right))
  end)

  it("draws a buffer no window shows and answers no windows", function()
    vim.cmd("silent only!")
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, other)
    local drawn = false
    local wins = redraw.windows(buf, function()
      drawn = true
    end)
    assert.is_true(drawn)
    assert.are.same({}, wins)
  end)
end)
