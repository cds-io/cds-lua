local document = require("cds.document")
local html = require("cds.html")

local function fixture(name)
  local file = assert(io.open("spec/fixtures/documents/" .. name, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

describe("shared document contract", function()
  for _, entry in ipairs({
    { "rssfeedr-page.html", "https://blog.nerdware.ca/2026/10/24/hot-singles-v1.html" },
    { "rfc-css-grid-2.html", "https://www.w3.org/TR/css-grid-2/" },
  }) do
    it("preserves the complete fixture contract for " .. entry[1], function()
      local expected = vim.json.decode(fixture(entry[1] .. ".document.json"))
      local actual, title = html.document(fixture(entry[1]), { base = entry[2], page = true })
      assert.same(expected.document, actual)
      assert.equals(expected.title, title)
    end)
  end

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
  it("attaches IDs to immediately emitted rules rather than the following block", function()
    local doc = html.document('<hr id="first"><h2 id="heading">Title</h2><hr id="last">')
    assert.equals("---", doc.markdown[assert(document.anchor(doc, "first"))])
    assert.equals("## Title", doc.markdown[assert(document.anchor(doc, "heading"))])
    assert.equals(#doc.markdown, document.anchor(doc, "last"))
    assert.equals("---", doc.markdown[document.anchor(doc, "last")])
    local between = html.document('<p id="before">Before</p><hr id="sep"><p id="after">After</p>')
    assert.equals("Before", between.markdown[between.anchors.before])
    assert.equals("---", between.markdown[between.anchors.sep])
    assert.equals("After", between.markdown[between.anchors.after])
  end)
  it("uses identical leftmost and cursor policies for source and rendered links", function()
    local source = document.new({ "[first long text](https://a) [x](https://b)" })
    local marks = {}
    for i = #source.links, 1, -1 do
      local link = source.links[i]
      marks[#marks + 1] =
        { lnum = link.lnum, col = link.col, end_col = link.end_col, link = link.target, hl = "Normal" }
    end
    local rendered = document.rendered(source, source.markdown, marks)
    assert.equals("https://a", document.target(source, nil, 1, 0, { first = true }))
    assert.equals("https://a", document.target(source, rendered, 1, 0, { first = true }))
    for col = 0, #source.markdown[1] - 1 do
      assert.equals(document.target(source, nil, 1, col), document.target(source, rendered, 1, col))
    end
    assert.equals("https://b", marks[1].link)
    assert.equals("https://a", source.links[1].target)
  end)

  it("keeps enclosing image links and ignores code while accepting edited Markdown", function()
    local source = document.new({ "[![alt](image.png)](https://outer)", "```md", "[code](https://code)", "```" })
    assert.equals("https://outer", document.target(source, nil, 1, 5))
    assert.equals("https://outer", document.target(source, nil, 1, 0, { first = true }))
    assert.is_nil(document.target(source, nil, 3, 0, { first = true, line = source.markdown[3] }))
    assert.equals("https://edited", document.target(source, nil, 1, 1, { line = "[new](https://edited)" }))
    assert.equals("https://outer", source.links[2].target)
  end)

  it("builds presentation data without river-specific fields or input mutation", function()
    local source = document.new({ "# Title" })
    local shown = { "Styled title" }
    local styled = document.rendered(source, shown, {}, true, { { 0, 1, 0, 1 } })
    assert.is_true(styled.source == source)
    assert.is_true(styled.styled)
    assert.is_true(styled.waiting)
    assert.same(shown, styled.lines)
    assert.is_nil(styled.rows)
    assert.is_nil(styled.folds)
    local plain = document.rendered(source, nil, nil, true)
    assert.is_false(plain.styled)
    assert.is_false(plain.waiting)
    assert.same({ "# Title" }, plain.lines)
    assert.same({ "# Title" }, source.markdown)
  end)
  it("lets source adapters select body metadata without losing anchors to an omitted head end tag", function()
    local input = '<html><head><title>Spec</title><body><header><h2 id="abstract">Abstract</h2></header>'
      .. '<main><h2 id="intro">Intro</h2></main></body></html>'
    local reader = html.document(input, { page = true })
    assert.is_nil(reader.anchors.abstract)
    local report = html.document(input, { page = true, region = "body", drop = { head = true, script = true } })
    assert.equals("## Abstract", report.markdown[report.anchors.abstract])
    assert.equals("## Intro", report.markdown[report.anchors.intro])
  end)

  it("ignores code spans and escaped link openers in both link selection paths", function()
    local line = "`[code](https://code)` ``[ticks](https://ticks) ` inside`` "
      .. "\\[escaped](https://escaped) [real `label`](https://real) <https://bare>"
    local doc = document.new({ line })
    assert.equals(2, #doc.links)
    for col = 0, #line - 1 do
      assert.equals(document.link(doc, 1, col), document.link_at(line, col))
    end
    assert.equals("https://real", document.target(doc, nil, 1, 0, { first = true }))
    assert.is_nil(document.link_at(line, 3))
    local generated = html.document("<p><code>[example](https://example.org)</code></p>")
    assert.same({}, generated.links)
    assert.same({}, document.new({ "`<https://code>`" }).links)
  end)

  it("keeps info strings and short markers inside their enclosing code fence", function()
    for _, mark in ipairs({ "`", "~" }) do
      local fence = string.rep(mark, 4)
      local lines = {
        fence .. "md",
        string.rep(mark, 3),
        fence .. "lang",
        "# Fake",
        "[x](https://fake)",
        fence .. "  ",
        "# Real",
        "[x](https://real)",
      }
      local doc = document.new(lines)
      assert.is_nil(doc.anchors.fake)
      assert.equals(7, doc.anchors.real)
      assert.equals(1, #doc.links)
      assert.equals("https://real", doc.links[1].target)
      assert.is_nil(document.target(doc, nil, 5, 1, { line = "[edited](https://edited)" }))
    end
  end)

  it("excludes links in multiline inline code emitted from HTML", function()
    local source =
      html.document('<p><code>first<br>[example](https://code)<br>last</code> <a href="https://real">real</a></p>')
    assert.equals(1, #source.links)
    assert.equals("https://real", source.links[1].target)
    assert.is_nil(document.target(source, nil, 2, 1))
    assert.is_nil(document.target(source, nil, 2, 1, { line = "[edited](https://edited)" }))
    local unmatched = document.new({ "`not closed", "[real](https://real)", "", "`another paragraph" })
    assert.equals("https://real", unmatched.links[1].target)
    local mixed = document.new({ "``start", "` [fake](https://fake)", "end`` [real](https://real)" })
    assert.equals(1, #mixed.links)
    assert.equals("https://real", mixed.links[1].target)
  end)

  it("allocates names without changing caller slugs or duplicate suffix policies", function()
    local bases = { "foo", "foo", "foo-1", "foo", "foo-2" }
    assert.same({ "foo", "foo-1", "foo-1-1", "foo-2", "foo-2-1" }, document.unique_names(bases))
    assert.same({ "foo", "foo-2", "foo-1", "foo-3", "foo-2-2" }, document.unique_names(bases, 2))
    assert.same({ "foo", "foo", "foo-1", "foo", "foo-2" }, bases)
    assert.same({}, document.unique_names({}))
  end)

  it("maps a source row to its rendered row and back through the blocks", function()
    local rendered = { styled = true, blocks = { { 0, 1, 0, 1 }, { 1, 9, 1, 18 } } }
    assert.equals(1, document.rendered_row(rendered, 1))
    assert.equals(2, document.rendered_row(rendered, 2))
    assert.equals(10, document.rendered_row(rendered, 6))
    assert.equals(6, document.source_row(rendered, 10))
    assert.equals(6, document.source_row(rendered, 11))
    assert.equals(1, document.source_row(rendered, 1))
    -- an unstyled layout maps rows to themselves
    assert.equals(7, document.rendered_row({ styled = false }, 7))
    assert.equals(7, document.source_row({ styled = false }, 7))
  end)
end)
