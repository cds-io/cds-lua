local html = require("cds.html")
local dom = require("cds.html.dom")
local format = require("cds.html.format")

describe("HTML5 DOM conversion", function()
  it("reports an actionable native dependency error without disabling pure helpers", function()
    local loaded, preload = package.loaded.gumbo, package.preload.gumbo
    package.loaded.gumbo = nil
    package.preload.gumbo = function()
      error("native module unavailable")
    end
    local ok, err = pcall(html.markdown, "<p>Hello</p>")
    local escaped = html.escape("*text*")
    package.loaded.gumbo, package.preload.gumbo = loaded, preload
    assert.is_false(ok)
    assert.matches("requires lua%-gumbo", err)
    assert.matches("Lua 5.1/LuaJIT", err, 1, true)
    assert.matches(":Lazy build lua-gumbo", err, 1, true)
    assert.matches("luarocks --lua-version=5.1 --local install gumbo 0.5-1", err, 1, true)
    assert.matches("native module unavailable", err, 1, true)
    assert.equals("\\*text\\*", escaped)
  end)

  it("keeps charset metadata out of comments, scripts and foreign text", function()
    local source = '<!-- <meta charset=wrong> --><script>"<meta charset=wrong>"</script>'
      .. '<svg><title>&lt;meta charset=wrong&gt;</title></svg><meta charset="utf&#45;8">'
    assert.equals("utf-8", html.charset(nil, source))
    assert.equals("windows-1252", html.charset("text/html; charset=windows-1252", source))
    assert.is_nil(html.charset(nil, string.rep(" ", 2048) .. "<meta charset=utf-8>"))
  end)

  it("selects the first nonempty content region and ignores foreign titles", function()
    local page = html.page(
      "<svg><title>Icon</title></svg><title>Page &amp; title</title>"
        .. "<main><nav>Menu</nav></main><article id=article><p>Hello</p></article>"
    )
    assert.equals("Page & title", page.title)
    assert.same({ "Hello" }, page.lines)
    assert.same({ article = 1 }, page.anchors)
  end)

  it("does not merge adjacent tables that both require generated headers", function()
    local lines, anchors = html.markdown(
      "<table><tr id=a><td>A</td></tr><tr><th>B</th></tr></table>"
        .. "<table><tr id=c><td>C</td></tr><tr><th>D</th></tr></table>"
    )
    assert.same({ "|  |", "| --- |", "| A |", "| B |", "", "|  |", "| --- |", "| C |", "| D |" }, lines)
    assert.same({ a = 3, c = 8 }, anchors)
  end)

  it("repairs omitted paragraphs and keeps empty conversion total", function()
    assert.same({ "First", "", "Second" }, html.markdown("<p>First<p>Second"))
    assert.same({}, html.markdown(""))
    assert.same({}, html.page("", {}).lines)
  end)

  it("roundtrips plain IR through JSON without a DOM", function()
    local tree = dom.parse('<blockquote><p id="x">Hello &amp; <em>world</em></p></blockquote>', true)
    local decoded = vim.json.decode(vim.json.encode(tree))
    local expected, anchors = format.blocks(dom.blocks(tree))
    local actual, actual_anchors = format.blocks(dom.blocks(decoded))
    assert.same({ "> Hello \\& *world*" }, actual)
    assert.same(expected, actual)
    assert.same(anchors, actual_anchors)
    assert.equals(1, actual_anchors.x)
  end)

  it("carries lexical inline ancestors through block boundaries", function()
    assert.same({ "*Before*", "", "*Inside*", "", "*After*" }, html.markdown("<em>Before<p>Inside</p>After</em>"))
  end)

  it("keeps the first duplicate attribute as HTML5 specifies", function()
    local lines, anchors = html.markdown("<p id=first id=last><a href=/first href=/last>Link</a></p>")
    assert.same({ "[Link](/first)" }, lines)
    assert.same({ first = 1 }, anchors)
  end)

  it("retains HTML5 formatting reconstruction across nested list and paragraph scopes", function()
    local source = "<ul><li><em>One<ul><li><strong>Two</ul></ul><p>After"
    assert.same({ "- *One*", "  - ***Two***", "", "***After***" }, html.markdown(source))
  end)

  it("retains a DOM link that encloses a later paragraph", function()
    assert.same(
      { "[one](/one)[two](/two)", "", "**[Next](/two)**" },
      html.markdown("<a href=/one>one<a href=/two>two<p><strong>Next")
    )
  end)

  it("does not strip a newline inside a pre's child code element", function()
    assert.same(
      { "```lua", "", "a < b", "```" },
      html.markdown("<pre><code class=language-lua>\na &lt; b</code></pre>")
    )
  end)

  it("decodes entities exactly once in text, targets and preformatted content", function()
    assert.same(
      { "\\&amp; © 😀 ≂̸ [A](/?a=1&b=2)" },
      html.markdown('<p>&amp;amp; &copy; &#x1f600; &NotEqualTilde; <a href="/?a=1&amp;b=2">A</a></p>')
    )
    assert.same({ "```", "&amp;", "```" }, html.markdown("<pre>&amp;amp;</pre>"))
  end)

  it("preserves pre descendants' IDs and strips the leading newline only once", function()
    local lines, anchors = html.markdown("<pre id=pre>\n\n<code id=code>a &lt; b</code></pre>")
    assert.same({ "```", "", "a < b", "```" }, lines)
    assert.same({ pre = 1, code = 1 }, anchors)
  end)

  it("returns a paragraph after a nested list to its parent item", function()
    assert.same(
      { "9. First", "   - Child", "   Tail", "10. Second" },
      html.markdown("<ol start=9><li>First<ul><li>Child</li></ul><p>Tail</p></li><li>Second</li></ol>")
    )
  end)

  it("preserves ordinary fragment whitespace and repairs omitted cells", function()
    assert.same({ "*a b*" }, html.markdown("<em>a</em> <strong></strong><em>b</em>"))
    local lines, anchors = html.markdown("<table><tr id=a><th>A<th>B<tr id=b><td>C<td>D</table>")
    assert.same({ "| A | B |", "| --- | --- |", "| C | D |" }, lines)
    assert.same({ a = 1, b = 3 }, anchors)
  end)
end)
