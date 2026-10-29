-- Image sources vellum cannot read, as files it can: a base64 data URI in a
-- Markdown image becomes a file under the cache directory, named by its
-- content. Runs inside Neovim (make test).
local sources = require("cds.vellum.sources")

local PNG = "\137PNG\r\n\26\n" .. ("\0"):rep(16)
local PNG64 = vim.base64.encode(PNG)

describe("cds.vellum.sources.materialise", function()
  local dir
  before_each(function()
    dir = vim.fn.tempname()
  end)
  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  local function files()
    return vim.fn.glob(dir .. "/*", false, true)
  end

  it("writes a base64 PNG to a content-named file and points the image at it", function()
    local markdown = { "text", "![alt](data:image/png;base64," .. PNG64 .. ")", "" }
    local lines = sources.materialise(markdown, dir)
    local path = dir .. "/" .. vim.fn.sha256(PNG) .. ".png"
    assert.same({ "text", "![alt](" .. path .. ")", "" }, lines)
    local f = assert(io.open(path, "rb"))
    assert.equal(PNG, f:read("*a"))
    f:close()
    assert.same({ path }, files())
    -- the caller's lines are its own
    assert.equal("![alt](data:image/png;base64," .. PNG64 .. ")", markdown[2])
  end)

  it("writes one file for one payload however often it appears", function()
    local image = "![a](data:image/png;base64," .. PNG64 .. ")"
    local lines = sources.materialise({ image, image .. " and [" .. image .. "](https://x/)" }, dir)
    assert.equal(1, #files())
    assert.is_nil(lines[2]:find("data:", 1, true))
  end)

  it("names the file by its media type", function()
    local lines = sources.materialise({
      "![j](data:image/jpeg;base64," .. PNG64 .. ")",
      "![s](data:image/svg+xml;base64," .. PNG64 .. ")",
      "![w](data:image/webp;base64," .. PNG64 .. ")",
    }, dir)
    assert.truthy(lines[1]:find("%.jpg%)$"))
    assert.truthy(lines[2]:find("%.svg%)$"))
    assert.truthy(lines[3]:find("%.webp%)$"))
  end)

  it("leaves every other source as it is", function()
    local markdown = {
      "![h](https://x/a.png)",
      "![p](/tmp/a.png)",
      "![t](data:image/svg+xml,%3Csvg%3E)",
      "![b](data:image/png;base64,***)",
      "![n](data:text/plain;base64," .. PNG64 .. ")",
      "a line with no image",
    }
    assert.same(markdown, sources.materialise(markdown, dir))
    assert.same({}, files())
  end)
end)
