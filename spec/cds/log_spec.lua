local log = require("cds.log")

local function records(path)
  local out = {}
  for line in io.lines(path) do
    table.insert(out, vim.json.decode(line))
  end
  return out
end

describe("cds.log", function()
  local path
  before_each(function()
    path = vim.fn.tempname() .. "/nested/test.log"
  end)

  it("appends one JSON object per line with a time, a level, an event and its fields", function()
    local l = log.new({ path = path, level = "info" })
    l:info("run", { buf = "todo.md", first = 1 })
    l:info("done", { created = 0 })
    local recs = records(path)
    assert.are.equal(2, #recs)
    assert.are.same({ "info", "run", { buf = "todo.md", first = 1 } }, { recs[1].level, recs[1].event, recs[1].fields })
    assert.truthy(recs[1].t:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$"))
    assert.are.equal("done", recs[2].event)
  end)

  it("starts every line with the time, the level and the event, in that order", function()
    local l = log.new({ path = path, level = "info" })
    l:info("run", { z = 1, a = 2 })
    local line = io.lines(path)()
    assert.truthy(line:match('^{"t":"[^"]+","level":"info","event":"run","fields":{'))
  end)

  it("keeps debug records only at the debug level, and nothing when off", function()
    local at_info = log.new({ path = path, level = "info" })
    at_info:debug("line", { n = 1 })
    at_info:info("run", {})
    local at_debug = log.new({ path = path, level = "debug" })
    at_debug:debug("line", { n = 2 })
    local off = log.new({ path = path, level = "off" })
    off:info("run", {})
    off:debug("line", {})
    local recs = records(path)
    assert.are.same({ "run", "line" }, { recs[1].event, recs[2].event })
    assert.are.equal(2, recs[2].fields.n)
    assert.are.equal(2, #recs)
  end)

  it("never raises: an unwritable path and an unencodable field are both swallowed", function()
    local bad = log.new({ path = "/dev/null/nope/test.log", level = "info" })
    assert.is_false(bad:info("run", {}))
    local l = log.new({ path = path, level = "info" })
    assert.is_true(l:info("odd", { fn = function() end }))
    local recs = records(path)
    assert.are.equal("odd", recs[1].event)
    assert.is_string(recs[1].fields.unencodable)
  end)

  it("works from a fast event context", function()
    local l = log.new({ path = path, level = "info" })
    local done, fast
    local timer = vim.uv.new_timer()
    timer:start(1, 0, function()
      timer:close()
      fast = vim.in_fast_event()
      done = l:info("from a callback", { ok = true })
    end)
    vim.wait(500, function()
      return done ~= nil
    end)
    assert.is_true(fast)
    assert.is_true(done)
    assert.are.equal("from a callback", records(path)[1].event)
  end)
end)
