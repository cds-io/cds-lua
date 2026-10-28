-- The article as vellum renders it: nil without vellum, its lines and marks
-- with it, nil and one warning when it fails. vellum is faked through
-- package.preload. Runs inside Neovim (make test-nvim).
local styled = require("cds.vellum")

local MARKDOWN = { "# Title one", "", "second" }

describe("styled.render", function()
  local fake, notices, real_notify

  --- The renderer under `fake`, the theme a no-op, both loaded afresh.
  local function install(render)
    fake = { calls = 0, applied = 0 }
    package.preload["vellum.render"] = function()
      return {
        reset = function() end,
        render = function(...)
          fake.calls = fake.calls + 1
          return render(...)
        end,
      }
    end
    package.preload["vellum.theme"] = function()
      return {
        apply = function()
          fake.applied = fake.applied + 1
        end,
      }
    end
  end

  before_each(function()
    package.loaded["vellum.render"], package.loaded["vellum.theme"] = nil, nil
    package.loaded["vellum.media"] = nil
    styled.forget()
    styled.restyle()
    notices = {}
    real_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notices, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = real_notify
    package.preload["vellum.render"], package.preload["vellum.theme"] = nil, nil
    package.loaded["vellum.render"], package.loaded["vellum.theme"] = nil, nil
    package.preload["vellum.media"], package.loaded["vellum.media"] = nil, nil
    styled.forget()
    styled.restyle()
  end)

  it("answers nil when vellum is not installed", function()
    package.preload["vellum.render"] = function()
      error("not found")
    end
    assert.is_nil(styled.render(MARKDOWN, 78))
    assert.same({}, notices)
  end)

  it("answers vellum's lines and its spans as marks shifted by the margin", function()
    local asked
    install(function(buf, width, measure)
      asked = { lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true), width = width, measure = measure }
      return { "  Title one", "  second" }, { { { 0, 3, "Title", 100 } } }, 2, { { 0, 1, 0, 1 } }
    end)
    local lines, marks = styled.render(MARKDOWN, 78)
    assert.same({ "  Title one", "  second" }, lines)
    assert.same({ { lnum = 1, col = 2, end_col = 5, hl = "Title", priority = 100 } }, marks)
    assert.same({ lines = MARKDOWN, width = 78, measure = 100 }, asked)
    assert.equals(1, fake.applied)
    assert.same({}, notices)
  end)

  it("carries a span's link on its mark, and only a link written as text", function()
    install(function()
      local spans = { { 0, 3, "Link", 100, "https://x/" }, { 4, 7, "Link", 100, { "wiki", "page" } } }
      return { "  Title one" }, { spans }, 2, {}
    end)
    local _, marks = styled.render(MARKDOWN, 78)
    assert.same({
      { lnum = 1, col = 2, end_col = 5, hl = "Link", priority = 100, link = "https://x/" },
      { lnum = 1, col = 6, end_col = 9, hl = "Link", priority = 100 },
    }, marks)
  end)

  it("answers whether the render raised vellum's count of output still rendering", function()
    local media = { pending = 3 }
    package.preload["vellum.media"] = function()
      return media
    end
    local raises = true
    install(function()
      if raises then
        media.pending = media.pending + 1
      end
      return { "  Title one" }, {}, 2, {}
    end)
    assert.is_true(select(3, styled.render(MARKDOWN, 78)))
    raises = false
    assert.is_false(select(3, styled.render(MARKDOWN, 78)))
  end)

  it("answers no waiting without vellum's media module", function()
    package.preload["vellum.media"] = function()
      error("not found")
    end
    install(function()
      return { "  Title one" }, {}, 2, {}
    end)
    assert.is_false(select(3, styled.render(MARKDOWN, 78)))
  end)

  it("applies the theme once until restyled", function()
    install(function()
      return { "  Title one" }, {}, 2, {}
    end)
    styled.render(MARKDOWN, 78)
    styled.render(MARKDOWN, 78)
    assert.equals(1, fake.applied)
    styled.restyle()
    styled.render(MARKDOWN, 78)
    assert.equals(2, fake.applied)
  end)

  it("answers nil and warns once when vellum throws", function()
    install(function()
      error("renderer broke")
    end)
    assert.is_nil(styled.render(MARKDOWN, 78))
    assert.is_nil(styled.render(MARKDOWN, 78))
    assert.equals(1, #notices)
    assert.equals(vim.log.levels.WARN, notices[1].level)
    assert.truthy(notices[1].msg:find("renderer broke", 1, true))
  end)

  it("answers nil for a span outside its line", function()
    install(function()
      return { "  Title" }, { { { 0, 40, "Title", 100 } } }, 2, {}
    end)
    assert.is_nil(styled.render(MARKDOWN, 78))
    assert.equals(1, #notices)
  end)

  it("answers nil for a block anchor outside the page", function()
    install(function()
      return { "  Title" }, {}, 2, { { 0, 9, 0, 1 } }
    end)
    assert.is_nil(styled.render(MARKDOWN, 78))
    assert.equals(1, #notices)
  end)

  it("moves its generation on restyle, so a render memo keyed by it lets the next render through", function()
    local before = styled.generation()
    styled.restyle()
    assert.equals(before + 1, styled.generation())
  end)
end)
