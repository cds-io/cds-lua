local scratch = require("cds.scratch")
local view, origin
before_each(function()
  origin = vim.api.nvim_get_current_win()
  view = scratch.new({ name = "[Cds Test]", filetype = "markdown" })
end)
after_each(function()
  view:destroy()
  if vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  vim.cmd("silent! only!")
end)

describe("cds.scratch", function()
  it("opens, focuses and hides one persistent buffer", function()
    local win = view:open({ kind = "vsplit", size = 0.5 })
    local buf = view:buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "retained" })
    assert.equal(win, view:open())
    view:hide()
    assert.is_nil(view:window())
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
    view:toggle()
    assert.equal(buf, vim.api.nvim_win_get_buf(view:window()))
    assert.same({ "retained" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("does not close or focus a window that switched to a different buffer", function()
    local win = view:open()
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, other)
    view:hide()
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.equal(other, vim.api.nvim_win_get_buf(win))
    assert.is_nil(view:window())
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it("recreates a wiped buffer and reruns creation hooks", function()
    local created = 0
    view.opts.on_create = function()
      created = created + 1
    end
    view:open()
    local first = view:buffer()
    vim.api.nvim_buf_delete(first, { force = true })
    assert.is_nil(view.buf)
    view:open()
    assert.not_equal(first, view:buffer())
    assert.equal(2, created)
  end)

  it("applies the show hook to native window entries", function()
    local shown = {}
    view.opts.on_show = function(buf, win)
      shown[#shown + 1] = { buf, win }
    end
    local buf = view:buffer()
    vim.cmd.vsplit()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    assert.same({ buf, win }, shown[#shown])
    assert.equal(win, view:window())
  end)

  it("resolves fresh float dimensions after hiding", function()
    local width = 10
    local opts = {
      kind = "float",
      float = {
        width = function()
          return width
        end,
        height = 3,
      },
    }
    local win = view:open(opts)
    assert.equal(10, vim.api.nvim_win_get_width(win))
    view:hide()
    width = 20
    win = view:open()
    assert.equal(20, vim.api.nvim_win_get_width(win))
  end)

  it("isolates independent view instances", function()
    local other = scratch.new({ name = "[Cds Other]" })
    view:open()
    other:open()
    local other_buf = other:buffer()
    view:destroy()
    assert.is_true(vim.api.nvim_buf_is_valid(other_buf))
    assert.is_number(other:window())
    other:destroy()
  end)
  it("hides a view displayed in the last native window", function()
    vim.api.nvim_win_set_buf(origin, view:buffer())
    view:hide()
    assert.is_nil(view:window())
    assert.is_true(vim.api.nvim_buf_is_valid(view:buffer()))
    assert.is_true(vim.api.nvim_win_is_valid(origin))
  end)

  it("cleans up a buffer when its creation hook raises", function()
    view.opts.on_create = function()
      error("cannot initialize")
    end
    assert.has_error(function()
      view:buffer()
    end)
    assert.is_nil(view.buf)
    assert.is_nil(view.win)
    view.opts.on_create = nil
    assert.is_number(view:buffer())
  end)
end)
