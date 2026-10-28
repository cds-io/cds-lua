local progress = require("cds.progress")

describe("cds.progress", function()
  local clock, report, changes
  before_each(function()
    clock = 1000
    changes = 0
    report = progress.new({
      title = "CRS reports by topic",
      plan = { "reading source", "parsing metadata", "filing" },
      now = function()
        return clock
      end,
    })
    report:subscribe(function()
      changes = changes + 1
    end)
  end)

  it("renders the title with the elapsed time and the planned phases pending", function()
    assert.same({
      "CRS reports by topic              0.0s",
      "· reading source",
      "· parsing metadata",
      "· filing",
    }, report:lines(38))
  end)

  it("draws a bar on a counted phase and marks a finished phase with its seconds", function()
    report:begin("reading source", 32)
    report:tick(16)
    clock = 4400
    assert.same({
      "CRS reports by topic              3.4s",
      "▸ reading source [████████░░░░░░░░] 16/32",
      "· parsing metadata",
      "· filing",
    }, report:lines(38))
    report:begin("parsing metadata")
    clock = 5600
    assert.same({
      "CRS reports by topic              4.6s",
      "✓ reading source 3.4s",
      "▸ parsing metadata",
      "· filing",
    }, report:lines(38))
    assert.equals(3, changes)
  end)

  it("says done in the title once finished, and the error on a failure", function()
    report:begin("reading source")
    clock = 1500
    report:finish()
    assert.equals("CRS reports by topic      done in 0.5s", report:lines(38)[1])
    assert.equals("✓ reading source 0.5s", report:lines(38)[2])
    assert.is_true(report:finished())
    local failed = progress.new({
      title = "T",
      plan = { "a" },
      now = function()
        return clock
      end,
    })
    failed:begin("a")
    failed:fail("HTTP 503 fetching the CRS index")
    assert.same(
      { "T                               failed", "✗ a: HTTP 503 fetching the CRS index" },
      failed:lines(38)
    )
    assert.is_true(failed:finished())
  end)

  it("appends a phase the plan did not name, and ticks by one unless told", function()
    report:begin("styling", 38)
    report:tick()
    report:tick()
    assert.equals("▸ styling [█░░░░░░░░░░░░░░░] 2/38", report:lines(38)[5])
    assert.equals("styling", report.phases[4].name)
    assert.equals(2, report.phases[4].count)
  end)

  it("stops telling an observer that unsubscribed", function()
    local seen = 0
    local off = report:subscribe(function()
      seen = seen + 1
    end)
    report:begin("filing")
    off()
    report:done()
    assert.equals(1, seen)
    assert.equals(2, changes)
  end)
end)
