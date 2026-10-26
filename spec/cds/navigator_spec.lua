local navigator = require("cds.navigator")
local document = require("cds.document")

describe("document tag navigation", function()
  local nav, origin, destination, win
  before_each(function()
    vim.cmd("silent only!")
    nav = navigator.new()
    origin = vim.api.nvim_create_buf(false, true)
    destination = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(origin, 0, -1, false, { "origin", "position" })
    vim.api.nvim_buf_set_lines(destination, 0, -1, false, { "title", "section" })
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, origin)
    vim.api.nvim_win_set_cursor(win, { 2, 3 })
  end)
  after_each(function()
    vim.cmd("silent only!")
    pcall(vim.api.nvim_buf_delete, origin, { force = true })
    pcall(vim.api.nvim_buf_delete, destination, { force = true })
  end)

  it("accepts application tag resolvers and records each completed move once", function()
    local pending, calls = nil, 0
    local function resolve(tag, done)
      assert.equals("rfc9110-3.1", tag)
      calls = calls + 1
      pending = done
    end
    local function open(buf, err, done)
      assert.is_nil(err)
      vim.api.nvim_win_set_buf(win, buf)
      done()
      done()
    end
    nav.follow(win, "rfc9110-3.1", resolve, open)
    nav.follow(win, "rfc9110-3.1", resolve, open)
    assert.equals(1, calls)
    pending(destination)
    assert.equals(2, nav.pop(win).view.lnum)
    assert.is_nil(nav.pop(win))
  end)

  it("ignores an older pending follow and a callback after the window moves away", function()
    local callbacks, opened = {}, 0
    local function resolve(tag, done)
      callbacks[tag] = done
    end
    local function open()
      opened = opened + 1
    end
    nav.follow(win, "old", resolve, open)
    nav.follow(win, "new", resolve, open)
    callbacks.old(destination)
    assert.equals(0, opened)
    vim.api.nvim_win_set_buf(win, destination)
    callbacks.new(destination)
    assert.equals(0, opened)
    assert.is_nil(nav.pop(win))
  end)

  it("isolates sessions and invalidates pending callbacks on reset", function()
    local pending
    nav.follow(win, "tag", function(_, done)
      pending = done
    end, function()
      error("stale callback")
    end)
    nav.reset()
    pending(destination)
    nav.remember(win, function(done)
      vim.api.nvim_win_set_buf(win, destination)
      done()
    end)
    assert.is_nil(navigator.new().pop(win))
    assert.is_not_nil(nav.pop(win))
  end)

  it("jumps to a contract anchor through the rendered line mapping", function()
    local doc = document.new({ "# Title", "body" }, { anchors = { explicit = 2 } })
    assert.is_true(
      nav.jump(win, doc, { styled = true, lines = { "title", "section" }, blocks = { { 0, 2, 0, 2 } } }, "explicit")
    )
    assert.equals(2, vim.api.nvim_win_get_cursor(win)[1])
    assert.is_false(nav.jump(win, doc, nil, "missing"))
  end)
  it("retains the originating buffer handle when its name is empty", function()
    assert.equals("", vim.api.nvim_buf_get_name(origin))
    nav.remember(win, function(done)
      vim.api.nvim_win_set_buf(win, destination)
      done()
    end)
    local entry = nav.pop(win)
    assert.equals(origin, entry.buf)
    assert.equals("", entry.name)
    assert.equals(2, entry.view.lnum)
  end)
  it("invalidates a pending follow on local jumps, history pops and remembered moves", function()
    for _, intent in ipairs({
      function()
        nav.jump(win, document.new({ "# One", "# Two" }), nil, "two")
      end,
      function()
        nav.pop(win)
      end,
      function()
        nav.remember(win, function() end)
      end,
      function()
        nav.cancel(win)
      end,
    }) do
      local pending, opened
      nav.follow(win, "pending", function(_, done)
        pending = done
      end, function()
        opened = true
      end)
      intent()
      pending(destination)
      assert.is_nil(opened)
      assert.equals(origin, vim.api.nvim_win_get_buf(win))
    end
  end)

  it("cancels only the intended window and permits a new follow afterwards", function()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    local pending, opened = {}, {}
    local function begin(target_win)
      nav.follow(target_win, "same", function(_, done)
        pending[target_win] = done
      end, function()
        opened[target_win] = true
      end)
    end
    begin(win)
    begin(other)
    nav.cancel(win)
    pending[win](destination)
    pending[other](destination)
    assert.is_nil(opened[win])
    assert.is_true(opened[other])
    begin(win)
    pending[win](destination)
    assert.is_true(opened[win])
  end)
end)
