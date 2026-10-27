local html = require("cds.html")

describe("HTML conversion boundaries", function()
  it("reads quoted and unquoted attributes, decoding values and keeping the last duplicate", function()
    local lines, anchors =
      html.markdown([[<div hidden id=old ID=section><a href='/old' HREF=/guide?a=1&amp;b=2>Guide</a>
      <img src=/image.png alt=Photo><a name=legacy>End</a></div>]])
    assert.same({ "[Guide](/guide?a=1&b=2) ![Photo](/image.png)End" }, lines)
    assert.same({ section = 1, legacy = 1 }, anchors)
    assert.same({ "[Guide](<a > b>)" }, html.markdown([[<a title="href=wrong" href="a > b">Guide</a>]]))
  end)

  it("keeps charset sniffing's first raw duplicate value", function()
    assert.equals("utf-8", html.charset(nil, [[<meta CHARSET=utf-8 charset='windows-1252'>]]))
    assert.equals(
      "windows-1252",
      html.charset(nil, [[<meta http-equiv=Content-Type content='text/html; charset=windows-1252'>]])
    )
    assert.equals("utf-8", html.charset(nil, [[<meta title='charset=wrong' charset="utf-8">]]))
    assert.equals("utf-8", html.charset("text/html; charset=utf-8", [[<meta charset=windows-1252>]]))
  end)

  it("retains the selected region's unquoted ID and base", function()
    local page = html.page([[<base href=/docs/><main id=region><a href=guide>Guide</a></main>]], {
      base = "https://example.test/",
    })
    assert.same({ "[Guide](https://example.test/docs/guide)" }, page.lines)
    assert.equals(1, page.anchors.region)
  end)

  it("keeps the first ID across paragraphs and table rows", function()
    local lines, anchors = html.markdown([[<p id="same">First</p><table>
      <tr id="same"><th>Head</th></tr><tr id="body"><td>Body</td></tr>
      <tr id="body"><td>Later</td></tr></table><p id="body">Last</p>]])
    assert.equals("First", lines[anchors.same])
    assert.equals("| Body |", lines[anchors.body])
  end)

  it("maps row anchors with real, inferred and generated headers inside quotes", function()
    for _, input in ipairs({
      { '<tr id="first"><th>First</th></tr><tr id="second"><td>Second</td></tr>', 1 },
      { '<tr id="first"><td>First</td></tr><tr id="second"><td>Second</td></tr>', 1 },
      { '<tr id="first"><td>First</td></tr><tr id="second"><th>Second</th></tr>', 3 },
    }) do
      local lines, anchors = html.markdown("<blockquote><table>" .. input[1] .. "</table></blockquote>")
      assert.equals(input[2], anchors.first)
      assert.equals("> | First |", lines[anchors.first])
      assert.equals("> | Second |", lines[anchors.second])
    end
  end)

  it("closes inline spans at cell and block transitions without leaking list or quote state", function()
    assert.same(
      {
        "> - *One*",
        ">   - **Two**",
        ">",
        "> | *Cell* | Next |",
        "> | --- | --- |",
        "",
        "After",
      },
      html.markdown(
        "<blockquote><ul><li><em>One<ul><li><strong>Two</ul></ul>"
          .. "<table><tr><td><em>Cell<td>Next</tr></table></blockquote><p>After</p>"
      )
    )
  end)

  it("keeps code, math and nested link emphasis through inline finishing", function()
    assert.same(
      { "*before [middle](/u) after* `a < b` $x$" },
      html.markdown([[<em>before </em><a href=/u><em>middle</em></a><em> after</em> <code>a &lt; b</code> \(x\)]])
    )
    assert.same(
      { "[one](/one)[two](/two)", "", "**Next**" },
      html.markdown("<a href=/one>one<a href=/two>two<p><strong>Next")
    )
  end)

  it("resets preformatted language and inline state between blocks", function()
    assert.same(
      { "```lua", "a < b", "```", "", "*After*", "", "```", "plain", "```" },
      html.markdown("<pre><code class=language-lua>\na &lt; b</code></pre><p><em>After</p><pre>plain</pre>")
    )
  end)

  it("merges long runs of adjacent emphasis with intervening whitespace and links", function()
    local fragments = {}
    for _ = 1, 1000 do
      fragments[#fragments + 1] = "<em>x</em> <a href='/u'><em>y</em></a> "
    end
    assert.same(
      { "*" .. (string.rep("x [y](/u) ", 1000):gsub(" $", "")) .. "*" },
      html.markdown(table.concat(fragments))
    )
  end)
end)
