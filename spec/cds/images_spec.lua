-- The one adapter over an image plugin, exercised through a stub backend;
-- without a backend every call is a no-op.
local images = require("cds.images")

describe("images", function()
  local placed, cleared, stub

  before_each(function()
    placed, cleared = {}, {}
    stub = {
      name = "stub",
      available = function()
        return true
      end,
      place = function(spec)
        table.insert(placed, spec)
        local placement = { buf = spec.buf, id = #placed }
        return placement
      end,
      clear = function(placement)
        table.insert(cleared, placement.id)
      end,
    }
  end)

  after_each(function()
    images._use(nil)
  end)

  it("is unavailable without a backend, and every call is then a no-op", function()
    images._use(false)
    assert.is_false(images.available())
    assert.is_nil(images.place({ buf = 1, win = 0, row = 1, url = "x.png", max_height = 10 }))
    images.clear(nil)
    images.clear_all(1)
  end)

  it("hands a placement to the backend and answers it", function()
    images._use(stub)
    assert.is_true(images.available())
    local p = images.place({ buf = 7, win = 0, row = 3, url = "https://x/a.png", max_height = 12 })
    assert.are.same({ { buf = 7, win = 0, row = 3, url = "https://x/a.png", max_height = 12 } }, placed)
    assert.are.equal(1, p.id)
  end)

  it("clears one placement, and every placement of a buffer and no other", function()
    images._use(stub)
    local a = images.place({ buf = 7, win = 0, row = 1, url = "a.png", max_height = 5 })
    images.place({ buf = 7, win = 0, row = 9, url = "b.png", max_height = 5 })
    images.place({ buf = 8, win = 0, row = 1, url = "c.png", max_height = 5 })
    images.clear(a)
    assert.are.same({ 1 }, cleared)
    images.clear_all(7)
    assert.are.same({ 1, 2 }, cleared)
    images.clear_all(8)
    assert.are.same({ 1, 2, 3 }, cleared)
  end)

  it("answers nil and the reason when the backend refuses", function()
    stub.place = function()
      return nil, "no terminal"
    end
    images._use(stub)
    local p, err = images.place({ buf = 7, win = 0, row = 1, url = "a.png", max_height = 5 })
    assert.is_nil(p)
    assert.are.equal("no terminal", err)
  end)

  it("asks image.nvim to cap the height at max_height rows of the window, never to scale to it", function()
    local captured
    package.loaded.image = {
      is_enabled = function()
        return true
      end,
      from_file = function(_, opts)
        captured = opts
        return nil
      end,
    }
    finally(function()
      package.loaded.image = nil
    end)
    images._use(images._backends[1])
    local win = vim.api.nvim_get_current_win()
    images.place({ buf = vim.api.nvim_get_current_buf(), win = win, row = 1, url = "/tmp/a.png", max_height = 10 })
    assert.is_nil(captured.height)
    assert.are.equal(10 / vim.api.nvim_win_get_height(win) * 100, captured.max_height_window_percentage)
  end)
end)
