-- A page handed over as a flat text dump: a PDF through a text extractor,
-- every line a break and no block element in sight. Runs inside Neovim.
local html = require("cds.html")

local function breaks(n)
  local out = {}
  for i = 1, n do
    out[i] = ("line %d of the report <br/>"):format(i)
  end
  return table.concat(out, "\n")
end

describe("cds.html.flattened", function()
  it("is true for a run of breaks with no block elements", function()
    assert.is_true(html.flattened("<div id='x'><b>Title</b><br/>" .. breaks(40) .. "</div>"))
  end)

  it("counts <br> however it is spelled", function()
    assert.is_true(html.flattened(("text<BR>"):rep(20) .. ("text<br >"):rep(20)))
  end)

  it("is false for prose in paragraphs, even with breaks inside them", function()
    assert.is_false(html.flattened(("<p>a line<br/>another</p>"):rep(40)))
  end)

  it("is false for a short run", function()
    assert.is_false(html.flattened(breaks(10)))
  end)

  it("weighs list items, cells, headings, pre and definitions as blocks", function()
    local blocks = "<h2>t</h2><li>i</li><td>c</td><th>h</th><pre>p</pre><blockquote>q</blockquote><dt>d</dt><dd>e</dd>"
    -- eight blocks a repetition: 35 breaks over 8 is four in five, over 16 two in three
    assert.is_true(html.flattened(blocks:rep(1) .. breaks(35)))
    assert.is_false(html.flattened(blocks:rep(2) .. breaks(35)))
  end)

  it("carries the notice both readers show", function()
    assert.truthy(html.FLATTENED_NOTICE:find("Upstream (at source) conversion error", 1, true))
  end)
end)
