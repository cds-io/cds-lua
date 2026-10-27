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
      assert.equals(1, calls)
      assert.is_true(model.doc.source == source)
      assert.same(source.markdown, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.equals(document.anchor(source, entry[2]), document.anchor(source, entry[2], model.doc))
      assert.is_not_nil(document.anchor(source, entry[2], model.doc))
      vim.api.nvim_exec_autocmds("ColorScheme", {})
      assert.equals(2, calls)
    end)
  end

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
end)
