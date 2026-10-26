local document = require("cds.document")
local html = require("cds.html")

local function fixture(name)
  local file = assert(io.open("spec/fixtures/documents/" .. name, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

describe("shared document contract", function()
  it("reads rssfeedr's real article with code and resolved links", function()
    local doc, title = html.document(fixture("rssfeedr-page.html"), {
      base = "https://blog.nerdware.ca/2026/10/24/hot-singles-v1.html",
      page = true,
    })
    assert.matches("Hot singles", title)
    local text = table.concat(doc.markdown, "\n")
    assert.truthy(text:find("Close your eyes", 1, true))
    assert.truthy(text:find("```", 1, true))
    assert.is_true(#doc.links > 0)
    for _, link in ipairs(doc.links) do
      assert.equals(link.target, document.link(doc, link.lnum, link.col))
    end
  end)

  it("reads rfc.nvim's W3C fixture and retains IDs that differ from heading slugs", function()
    local base = "https://www.w3.org/TR/css-grid-2/"
    local doc, title = html.document(fixture("rfc-css-grid-2.html"), { base = base, page = true })
    assert.equals("CSS Grid Layout Module Level 2", title)
    local row = assert(document.anchor(doc, "intro"))
    assert.matches("Introduction", doc.markdown[row])
    assert.matches("Background and Motivation", doc.markdown[assert(document.anchor(doc, "background"))])
    local found = false
    for _, link in ipairs(doc.links) do
      if link.target == base .. "#subgrids" then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("preserves named, nested, region and percent-encoded anchors through headers", function()
    local doc = html.document(
      [[<main id="region"><a name="legacy"></a><h2 id="sec:1">Visible heading</h2>
      <p id="résumé">Read <a href="#sec:1">here</a> or <a href="mailto:x@y">mail</a>.</p></main>]],
      { base = "https://x.test/page?q=1", page = true }
    )
    local prefixed = document.prepend(doc, { "# Plugin header", "" })
    assert.equals(1, document.anchor(doc, "region"))
    assert.equals(3, document.anchor(prefixed, "legacy"))
    assert.equals(3, document.anchor(prefixed, "sec:1"))
    assert.matches("Read", prefixed.markdown[assert(document.anchor(prefixed, "r%C3%A9sum%C3%A9"))])
    assert.equals("https://x.test/page?q=1#sec:1", prefixed.links[1].target)
    assert.equals("mailto:x@y", prefixed.links[2].target)
    assert.equals(1, doc.anchors["sec:1"])
  end)

  it("maps explicit anchors through wrapped and compressed vellum blocks", function()
    local doc = document.new({ "# Heading", "", "paragraph", "more" }, { anchors = { custom = 4 } })
    assert.equals(
      8,
      document.anchor(doc, "custom", {
        styled = true,
        lines = {},
        blocks = { { 2, 2, 7, 5 } },
      })
    )
    assert.equals(
      5,
      document.anchor(doc, "custom", {
        styled = true,
        lines = {},
        blocks = { { 0, 4, 1, 4 } },
      })
    )
    assert.is_nil(document.anchor(doc, "missing"))
  end)

  it("keeps duplicate heading anchors distinct and ignores fenced code", function()
    local doc = document.new({ "# Intro", "```md", "# Fake", "[fake](https://fake)", "```", "# Intro" })
    assert.equals(1, document.anchor(doc, "intro"))
    assert.equals(6, document.anchor(doc, "intro-1"))
    assert.is_nil(document.anchor(doc, "fake"))
    assert.same({}, doc.links)
  end)

  it("keeps links and anchors in separate table rows", function()
    local doc = html.document(
      [[<table><tr id="head"><th>Name</th></tr>
      <tr id="row"><td><a href="/next">next</a></td></tr></table>]],
      { base = "https://x.test" }
    )
    assert.equals(1, document.anchor(doc, "head"))
    assert.equals(3, document.anchor(doc, "row"))
    assert.equals("https://x.test/next", doc.links[1].target)
  end)

  it("prefers an enclosing link over its nested image and uses byte columns", function()
    local doc = document.new({ "é [![alt](image.png)](https://x.test)" })
    assert.equals("https://x.test", document.link(doc, 1, 8))
    assert.is_nil(document.link(doc, 1, 0))
  end)
end)
