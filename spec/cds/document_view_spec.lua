local html = require("cds.html")
local document = require("cds.document")
local views = require("cds.document_view")

describe("shared document display", function()
  local buf
  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  for _, entry in ipairs({
    { "rssfeedr-page.html", "hot-singles-in-your-area-vol1" },
    { "rfc-css-grid-2.html", "intro" },
  }) do
    it("displays the source contract for " .. entry[1] .. " through a vellum-compatible renderer", function()
      local file = assert(io.open("spec/fixtures/documents/" .. entry[1], "rb"))
      local body = file:read("*a")
      file:close()
      local source = html.document(body, { base = "https://example.test/document", page = true })
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local model = { buf = buf, document = source }
      local calls = 0
      local view = views.new({
        current = function(candidate)
          return candidate == model
        end,
        render = function(markdown)
          calls = calls + 1
          assert.same(source.markdown, markdown)
          return markdown, {}, false, { { 0, #markdown, 0, #markdown } }
        end,
        draw = function(target, rendered)
          vim.api.nvim_buf_set_lines(target, 0, -1, false, rendered.lines)
        end,
        attach = function() end,
        attach_window = function() end,
        image_wait = function()
          return 1
        end,
        group = "cds_document_test",
        filetype = "markdown",
      })
      view.show(model)
      assert.is_true(vim.wait(500, function()
        return calls == 1
      end))
      assert.is_true(model.doc.source == source)
      assert.same(source.markdown, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.equals(document.anchor(source, entry[2]), document.anchor(source, entry[2], model.doc))
      assert.is_not_nil(document.anchor(source, entry[2], model.doc))
      vim.api.nvim_exec_autocmds("ColorScheme", {})
      assert.equals(2, calls)
    end)
  end

  --- A renderer that doubles every line after the title, so rendered rows
  --- differ from source rows: block one is the title, block two the rest.
  local function doubling(markdown)
    local lines = { markdown[1] }
    for i = 2, #markdown do
      lines[#lines + 1] = markdown[i]
      lines[#lines + 1] = ""
    end
    return lines, {}, false, { { 0, 1, 0, 1 }, { 1, #markdown - 1, 1, 2 * (#markdown - 1) } }
  end
  local function ten_lines()
    local lines = { "# Title" }
    for i = 2, 10 do
      lines[i] = "line " .. i
    end
    return lines
  end
  local function eager_view(model, opts)
    local calls = 0
    local view = views.new({
      current = function(candidate)
        return candidate == model and vim.api.nvim_buf_is_valid(model.buf)
      end,
      render = function(markdown)
        calls = calls + 1
        return doubling(markdown)
      end,
      draw = function(target, rendered)
        vim.bo[target].modifiable = true
        vim.api.nvim_buf_set_lines(target, 0, -1, false, rendered.lines)
      end,
      attach = function() end,
      attach_window = function() end,
      image_wait = function()
        return 1
      end,
      group = "cds_eager_test_" .. model.buf,
      filetype = "styled",
      style_delay = (opts or {}).style_delay or 1,
    })
    return view, function()
      return calls
    end
  end

  it("draws the Markdown at once and the styled lines after the delay", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local markdown = ten_lines()
    local model = { buf = buf, document = document.new(markdown) }
    local view, calls = eager_view(model, { style_delay = 50 })
    view.show(model)
    assert.equals(0, calls())
    assert.same(markdown, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.equals("markdown", vim.bo[buf].filetype)
    assert.is_false(model.doc.styled)
    assert.is_true(vim.wait(500, function()
      return calls() == 1
    end))
    assert.equals(19, vim.api.nvim_buf_line_count(buf))
    assert.equals("styled", vim.bo[buf].filetype)
    assert.is_true(model.doc.styled)
  end)

  it("keeps the cursor on the same source line across the styled draw and a redraw", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new(ten_lines()) }
    local view, calls = eager_view(model, { style_delay = 50 })
    view.show(model)
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    assert.is_true(vim.wait(500, function()
      return calls() == 1
    end))
    -- source row 6 is the fifth line of the doubled block: rendered row 1 + 1 + 2 * 4
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    assert.equals(2, calls())
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("styles a document shown hidden when its window shows it", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new(ten_lines()) }
    local view, calls = eager_view(model, { style_delay = 10 })
    view.show(model)
    vim.cmd("tabnew")
    local other = vim.api.nvim_get_current_tabpage()
    vim.wait(100)
    assert.equals(0, calls())
    vim.cmd("tabprevious")
    assert.is_true(vim.wait(500, function()
      return calls() == 1
    end))
    assert.is_true(model.doc.styled)
    vim.api.nvim_set_current_tabpage(other)
    vim.cmd("tabclose")
  end)

  it("applies the views handed to show after the styled draw", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new(ten_lines()) }
    local view, calls = eager_view(model, { style_delay = 10 })
    local win = vim.api.nvim_get_current_win()
    local saved = { lnum = 12, col = 0, topline = 1, leftcol = 0, coladd = 0, curswant = 0, skipcol = 0, topfill = 0 }
    view.show(model, { views = { [win] = saved } })
    assert.is_true(vim.wait(500, function()
      return calls() == 1
    end))
    assert.equals(12, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("refreshes a styled document when returning after a hidden colorscheme change", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new({ "# Title" }) }
    local calls = 0
    local view = views.new({
      current = function(candidate)
        return candidate == model and vim.api.nvim_buf_is_valid(buf)
      end,
      render = function(lines)
        calls = calls + 1
        return lines, {}, false, { { 0, 1, 0, 1 } }
      end,
      draw = function() end,
      attach = function() end,
      attach_window = function() end,
      image_wait = function()
        return 1
      end,
      group = "cds_hidden_document_test",
      filetype = "markdown",
    })
    view.show(model)
    assert.is_true(vim.wait(500, function()
      return calls == 1
    end))
    vim.cmd("tabnew")
    local other = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    assert.equals(1, calls)
    vim.cmd("tabprevious")
    assert.equals(2, calls)
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    assert.equals(2, calls)
    vim.api.nvim_set_current_tabpage(other)
    vim.cmd("tabclose")
  end)

  it("resumes a pending image after its retry was skipped in another tab", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new({ "image" }) }
    local calls = 0
    local view = views.new({
      current = function(candidate)
        return candidate == model and vim.api.nvim_buf_is_valid(buf)
      end,
      render = function(lines)
        calls = calls + 1
        return lines, {}, calls == 1, { { 0, 1, 0, 1 } }
      end,
      draw = function() end,
      attach = function() end,
      attach_window = function() end,
      image_wait = function()
        return 1
      end,
      group = "cds_hidden_image_test",
      filetype = "markdown",
    })
    view.show(model)
    assert.is_true(vim.wait(500, function()
      return calls == 1
    end))
    vim.cmd("tabnew")
    local other = vim.api.nvim_get_current_tabpage()
    vim.wait(20)
    assert.equals(1, calls)
    vim.cmd("tabprevious")
    local resumed = vim.wait(500, function()
      return calls == 2
    end)
    local waiting = model.doc.waiting
    vim.api.nvim_set_current_tabpage(other)
    vim.cmd("tabclose")
    assert.is_true(resumed)
    assert.is_false(waiting)
  end)

  it("does not duplicate or restart exhausted image retries on entry", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local model = { buf = buf, document = document.new({ "image" }) }
    local calls = 0
    views
      .new({
        current = function(candidate)
          return candidate == model and vim.api.nvim_buf_is_valid(buf)
        end,
        render = function(lines)
          calls = calls + 1
          return lines, {}, true, { { 0, 1, 0, 1 } }
        end,
        draw = function() end,
        attach = function() end,
        attach_window = function() end,
        image_wait = function()
          return 1
        end,
        group = "cds_image_budget_test",
        filetype = "markdown",
      })
      .show(model)
    assert.is_true(vim.wait(500, function()
      return calls == 1
    end))
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    assert.equals(1, calls)
    assert.is_true(vim.wait(1000, function()
      return calls == 7
    end))
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    vim.wait(20)
    assert.equals(7, calls)
  end)
end)
