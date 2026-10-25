local companion = require("cds.companion")
local manager, owner, source, allowed, buffers

local function document()
  local buf = vim.api.nvim_create_buf(false, true)
  buffers[#buffers + 1] = buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
  return buf
end

before_each(function()
  owner = vim.api.nvim_get_current_win()
  allowed, buffers = {}, {}
  source = document()
  allowed[source] = true
  vim.api.nvim_win_set_buf(owner, source)
  manager = companion.new({
    filetype = "example-contents",
    width = 20,
    window = { winfixwidth = true, cursorline = true },
    accept = function(buf)
      return allowed[buf]
    end,
    on_update = function(view, buf)
      view.data.updates = (view.data.updates or 0) + 1
      view.data.source = buf
      vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "first", "second", "third" })
    end,
    on_track = function(view)
      vim.api.nvim_win_set_cursor(view.win, vim.api.nvim_win_get_cursor(view.owner))
    end,
  })
end)

after_each(function()
  manager:close_all()
  vim.wait(10)
  vim.cmd("silent! only!")
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end)

local function tick(test)
  assert.is_true(vim.wait(500, test))
end

describe("cds.companion", function()
  it("gives two windows on one buffer independent views and cursor tracking", function()
    vim.cmd.vsplit()
    local second = vim.api.nvim_get_current_win()
    local first_view = assert(manager:open(owner))
    local second_view = assert(manager:open(second))
    assert.not_equal(first_view.buf, second_view.buf)
    assert.equal(source, first_view.source_buf)
    assert.equal(source, second_view.source_buf)
    vim.api.nvim_set_current_win(second)
    vim.api.nvim_win_set_cursor(second, { 3, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = source })
    assert.equal(3, vim.api.nvim_win_get_cursor(second_view.win)[1])
    assert.equal(1, vim.api.nvim_win_get_cursor(first_view.win)[1])
    manager:close(owner)
    assert.is_number(manager:get(second).win)
    assert.is_true(vim.api.nvim_win_is_valid(owner))
  end)

  it("updates accepted replacements and closes on rejected ones", function()
    local view = assert(manager:open(owner))
    local next_buf = document()
    allowed[next_buf] = true
    vim.api.nvim_win_set_buf(owner, next_buf)
    assert.equal(next_buf, view.data.source)
    assert.equal(2, view.data.updates)
    allowed[source] = false
    vim.api.nvim_win_set_buf(owner, source)
    assert.is_nil(manager:get(owner))
    assert.is_false(vim.api.nvim_win_is_valid(view.win))
    assert.is_true(vim.api.nvim_win_is_valid(owner))
  end)

  it("waits one turn for an unfinished replacement buffer", function()
    local view = assert(manager:open(owner))
    local pending = document()
    vim.api.nvim_win_set_buf(owner, pending)
    assert.equal(source, view.source_buf)
    allowed[pending] = true
    tick(function()
      return view.source_buf == pending
    end)
    assert.equal(2, view.data.updates)
  end)

  it("ignores a deferred answer for a view that was closed and reopened", function()
    local old = assert(manager:open(owner))
    local pending = document()
    vim.api.nvim_win_set_buf(owner, pending)
    manager:close(owner)
    allowed[pending] = true
    local current = assert(manager:open(owner))
    allowed[pending] = false
    vim.wait(10)
    assert.not_equal(old.buf, current.buf)
    assert.equal(current, manager:get(owner))
    assert.equal(1, current.data.updates)
  end)

  it("ignores a deferred answer when the owner has moved to a newer buffer", function()
    local view = assert(manager:open(owner))
    local pending, latest = document(), document()
    vim.api.nvim_win_set_buf(owner, pending)
    allowed[latest] = true
    vim.api.nvim_win_set_buf(owner, latest)
    allowed[pending] = false
    vim.wait(10)
    assert.equal(view, manager:get(owner))
    assert.equal(latest, view.source_buf)
    assert.equal(2, view.data.updates)
  end)

  it("forgets an externally closed companion and releases its resources", function()
    local view = assert(manager:open(owner))
    vim.api.nvim_win_close(view.win, true)
    assert.is_nil(manager:get(owner))
    tick(function()
      return not vim.api.nvim_buf_is_valid(view.buf)
    end)
    assert.is_true(vim.api.nvim_win_is_valid(owner))
  end)

  it("keeps a repurposed companion window and its new buffer intact", function()
    local view = assert(manager:open(owner))
    local other = document()
    vim.api.nvim_win_set_buf(view.win, other)
    assert.is_nil(manager:get(owner))
    tick(function()
      return not vim.wo[view.win].winfixwidth
    end)
    assert.is_true(vim.api.nvim_win_is_valid(view.win))
    assert.equal(other, vim.api.nvim_win_get_buf(view.win))
  end)

  it("defers owner-close teardown and ignores floats when preserving the last native window", function()
    vim.cmd("only")
    local view = assert(manager:open(owner))
    local float_buf = document()
    local float = vim.api.nvim_open_win(float_buf, false, {
      relative = "editor",
      width = 5,
      height = 1,
      row = 0,
      col = 0,
    })
    vim.api.nvim_set_current_win(owner)
    vim.cmd.quit()
    assert.is_nil(manager:get(owner))
    tick(function()
      return vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_buf(view.win) ~= view.buf
    end)
    assert.is_false(vim.wo[view.win].winfixwidth)
    assert.is_false(vim.api.nvim_buf_is_valid(view.buf))
    vim.api.nvim_win_close(float, true)
  end)

  it("refreshes content but leaves a focused companion's selection alone", function()
    local view = assert(manager:open(owner))
    vim.api.nvim_win_set_cursor(view.win, { 2, 0 })
    manager:track(owner)
    assert.equal(2, vim.api.nvim_win_get_cursor(view.win)[1])
    manager:refresh(owner)
    assert.equal(2, view.data.updates)
  end)

  it("cleans up after a creation hook fails", function()
    manager.opts.on_create = function()
      error("cannot initialize")
    end
    local windows = #vim.api.nvim_list_wins()
    assert.has_error(function()
      manager:open(owner)
    end)
    assert.is_nil(manager:get(owner))
    assert.equal(windows, #vim.api.nvim_list_wins())
    assert.is_true(vim.api.nvim_win_is_valid(owner))
  end)
end)
