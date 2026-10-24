local activity = require("cds.activity")
local async = require("cds.async")

describe("cds.activity", function()
  local clock, act, fired

  before_each(function()
    clock = 1000
    fired = 0
    act = activity.new({
      autocmd = "CdsActivityTest",
      now = function()
        return clock
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      pattern = "CdsActivityTest",
      callback = function()
        fired = fired + 1
      end,
    })
  end)

  after_each(function()
    act:reset()
    vim.api.nvim_clear_autocmds({ event = "User", pattern = "CdsActivityTest" })
  end)

  it("names every run out with its seconds, oldest first", function()
    assert.are.equal("", act:segment())
    assert.is_false(act:busy())
    local a = act:begin("events", "google")
    clock = 3500
    local b = act:begin("schedule", "macos")
    clock = 5200
    assert.are.equal("⟳ events google 4s · ⟳ schedule macos 1s", act:segment())
    assert.is_true(act:busy())
    act:finish(a)
    assert.are.equal("⟳ schedule macos 1s", act:segment())
    act:finish(b)
    assert.are.equal("", act:segment())
    assert.is_false(act:busy())
  end)

  it("fires the autocmd on both edges, and once per edge", function()
    local id = act:begin("events", "google")
    assert.are.equal(1, fired)
    act:finish(id)
    assert.are.equal(2, fired)
    act:finish(id) -- an id already ended
    assert.are.equal(2, fired)
  end)

  it("keeps the redraw timer only while something is out", function()
    assert.is_nil(act.timer)
    local id = act:begin("events", "google")
    assert.is_not_nil(act.timer)
    act:finish(id)
    assert.is_nil(act.timer)
  end)

  it("tracks a task to its end, whether it returns, raises or is closed", function()
    local gate = async.run(function()
      async.sleep(50)
      return "ok"
    end)
    act:track("events", "google", gate)
    assert.is_true(act:busy())
    assert.are.equal("ok", gate:wait(1000))
    vim.wait(100, function()
      return not act:busy()
    end)
    assert.is_false(act:busy())

    local failing = async.run(function()
      async.sleep(10)
      error("boom")
    end)
    act:track("events", "google", failing)
    assert.has_error(function()
      failing:wait(1000)
    end)
    vim.wait(100, function()
      return not act:busy()
    end)
    assert.is_false(act:busy())

    local long = async.run(function()
      async.sleep(10000)
    end)
    act:track("events", "google", long)
    long:close()
    vim.wait(200, function()
      return not act:busy()
    end)
    assert.is_false(act:busy())
    assert.are.equal(6, fired)
  end)
end)
