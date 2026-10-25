local pick = require("cds.pick")

local active, original, buf
before_each(function()
  original = vim.api.nvim_get_current_win()
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(original, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_win_set_cursor(original, { 2, 1 })
end)

after_each(function()
  if active then
    active.close()
  end
  vim.wait(50, function()
    return not active or not vim.api.nvim_buf_is_valid(active.buf)
  end)
  vim.api.nvim_set_current_win(original)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  active = nil
end)

local function press(key)
  local mapping = vim.fn.maparg(key, "n", false, true)
  assert.is_function(mapping.callback)
  mapping.callback()
end

describe("pick.keys", function()
  it("keeps home-row single keys for small lists", function()
    assert.same({ "a", "s", "d" }, pick.keys(3))
  end)

  it("has no prefix collisions across multiple key lengths", function()
    for _, count in ipairs({ 26, 27, 677 }) do
      local keys, seen = pick.keys(count), {}
      assert.equal(count, #keys)
      for _, key in ipairs(keys) do
        assert.is_nil(seen[key])
        assert.equal(#keys[1], #key)
        seen[key] = true
      end
    end
  end)
end)

describe("pick.select", function()
  it("selects the original item once after releasing its UI and restores the view", function()
    local items, calls, selected = { { name = "first" }, { name = "second" } }, 0, nil
    active = pick.select(items, {
      format_item = function(item)
        return item.name
      end,
    }, function(item)
      calls, selected = calls + 1, item
      assert.is_false(vim.api.nvim_buf_is_valid(active.buf))
      assert.equal(original, vim.api.nvim_get_current_win())
    end)
    press("s")
    active.close()
    assert(vim.wait(100, function()
      return calls == 1
    end))
    assert.equal(items[2], selected)
    assert.same({ 2, 1 }, vim.api.nvim_win_get_cursor(original))
  end)

  it("cancels on Escape without calling back twice", function()
    local calls = 0
    active = pick.select({ "one", "two" }, {}, function(item)
      calls = calls + 1
      assert.is_nil(item)
    end)
    press("<Esc>")
    active.close()
    assert(vim.wait(100, function()
      return calls == 1
    end))
  end)

  it("releases the buffer when the window is closed externally", function()
    local calls = 0
    active = pick.select({ "one", "two" }, {}, function(item)
      calls = calls + 1
      assert.is_nil(item)
    end)
    vim.api.nvim_win_close(active.win, true)
    assert(vim.wait(100, function()
      return calls == 1
    end))
    assert.is_false(vim.api.nvim_buf_is_valid(active.buf))
  end)

  it("cancels on leaving without moving focus back", function()
    local calls = 0
    active = pick.select({ "one", "two" }, {}, function()
      calls = calls + 1
    end)
    vim.api.nvim_set_current_win(original)
    assert(vim.wait(100, function()
      return calls == 1
    end))
    assert.equal(original, vim.api.nvim_get_current_win())
    assert.is_false(vim.api.nvim_win_is_valid(active.win))
  end)

  it("does not assign keys to headings", function()
    local chosen
    active = pick.select({ "heading", "one", "two" }, {
      selectable = function(item)
        return item ~= "heading"
      end,
    }, function(item)
      chosen = item
    end)
    press("a")
    assert(vim.wait(100, function()
      return chosen ~= nil
    end))
    assert.equal("one", chosen)
  end)

  it("schedules singleton and empty selections without opening a float", function()
    local calls, answer = 0, "pending"
    assert.is_nil(pick.select({}, {}, function(item)
      calls, answer = calls + 1, item
    end))
    assert.equal(0, calls)
    assert(vim.wait(100, function()
      return calls == 1
    end))
    assert.is_nil(answer)
    assert.is_nil(pick.select({ "only" }, {}, function(item)
      answer = item
    end))
    assert(vim.wait(100, function()
      return answer == "only"
    end))
    assert.equal(original, vim.api.nvim_get_current_win())
  end)

  it("clamps Unicode content to a small editor", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local ok, err = pcall(function()
      vim.o.columns, vim.o.lines = 20, 10
      active = pick.select({ string.rep("界", 50), "two" }, {}, function() end)
      local config = vim.api.nvim_win_get_config(active.win)
      assert.is_true(config.width <= 16)
      assert.is_true(config.height <= 6)
    end)
    vim.o.columns, vim.o.lines = columns, lines
    assert(ok, err)
  end)
end)
