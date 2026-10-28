local Task = require("cds.task")
local async = require("cds.async")

describe("cds.task", function()
  it("is lazy and starts a fresh run each time", function()
    local calls = 0
    local task = Task.new(function()
      calls = calls + 1
      return calls
    end):map(function(n)
      return n * 2
    end)
    assert.are.equal(0, calls)
    assert.are.equal(2, task:run():wait(1000))
    assert.are.equal(4, task:run():wait(1000))
  end)

  it("binds nil and false successes and skips continuations on errors", function()
    for _, task in ipairs({ Task.of(nil), Task.of(false) }) do
      assert.are.equal(
        "bound",
        task
          :bind(function()
            return Task.of("bound")
          end)
          :run()
          :wait(1000)
      )
    end
    local called = false
    local value, err = Task.fail(false)
      :map(function()
        called = true
      end)
      :run()
      :wait(1000)
    assert.is_nil(value)
    assert.is_false(err)
    assert.is_false(called)
  end)

  it("taps a value for its effect and passes it on, and never taps an error", function()
    local seen = {}
    local function note(value)
      seen[#seen + 1] = value
    end
    assert.is_false(Task.of(false):tap(note):run():wait(1000))
    local value, err = Task.fail("no"):tap(note):run():wait(1000)
    assert.is_nil(value)
    assert.are.equal("no", err)
    assert.are.same({ false }, seen)
  end)

  it("ensures a predicate, failing with a fixed or a built reason", function()
    local function even(n)
      return n % 2 == 0
    end
    assert.are.equal(4, Task.of(4):ensure(even, "odd"):run():wait(1000))
    local _, err = Task.of(3):ensure(even, "odd"):run():wait(1000)
    assert.are.equal("odd", err)
    _, err = Task.of(3)
      :ensure(even, function(n)
        return n .. " is odd"
      end)
      :run()
      :wait(1000)
    assert.are.equal("3 is odd", err)
    local called = false
    _, err = Task.fail("earlier")
      :ensure(function()
        called = true
        return true
      end, "unused")
      :run()
      :wait(1000)
    assert.are.equal("earlier", err)
    assert.is_false(called)
  end)

  it("lifts a Result, keeping false and zero and failing on nil with the error", function()
    assert.is_false(Task.of_result(false):run():wait(1000))
    assert.are.equal(0, Task.of_result(0, "ignored"):run():wait(1000))
    local value, err = Task.of_result(nil, "refused"):run():wait(1000)
    assert.is_nil(value)
    assert.are.equal("refused", err)
    assert.has_error(function()
      Task.of_result(nil, nil)
    end)
  end)

  it("binds a step in the Result convention, failing with the step's error", function()
    local function half(n)
      if n % 2 == 1 then
        return nil, n .. " is odd"
      end
      return n / 2
    end
    assert.are.equal(2, Task.of(4):bind_result(half):run():wait(1000))
    local value, err = Task.of(3):bind_result(half):run():wait(1000)
    assert.is_nil(value)
    assert.are.equal("3 is odd", err)
    local called = false
    value, err = Task.fail("earlier")
      :bind_result(function()
        called = true
        return 1
      end)
      :run()
      :wait(1000)
    assert.is_nil(value)
    assert.are.equal("earlier", err)
    assert.is_false(called)
  end)

  it("maps an error and leaves a value, false included, untouched", function()
    local function describe(err)
      return "fetching x: " .. err
    end
    assert.is_false(Task.of(false):map_err(describe):run():wait(1000))
    local value, err = Task.fail("timeout"):map_err(describe):run():wait(1000)
    assert.is_nil(value)
    assert.are.equal("fetching x: timeout", err)
    local calls = 0
    value = Task.fail(1)
      :map_err(function(n)
        calls = calls + 1
        return n + 1
      end)
      :recover(function(n)
        return Task.of(n * 10)
      end)
      :run()
      :wait(1000)
    assert.are.equal(20, value)
    assert.are.equal(1, calls)
  end)

  it("contains exceptions and recovers after yielding", function()
    local task = Task.new(function()
      async.sleep(5)
      error("broken request")
    end):recover(function(err)
      assert.truthy(tostring(err):find("broken request", 1, true))
      return Task.of("recovered")
    end)
    assert.are.equal("recovered", task:run():wait(1000))
  end)

  it("moves a fast-event result onto the main loop before mapping", function()
    local task = Task.new(function()
      return async.await(1, function(done)
        local timer = vim.uv.new_timer()
        timer:start(1, 0, function()
          timer:stop()
          timer:close()
          done("answer")
        end)
      end)
    end)
      :on_main()
      :map(function(value)
        assert.is_false(vim.in_fast_event())
        return value
      end)
    local value, err = task:run():wait(1000)
    assert.is_nil(err)
    assert.are.equal("answer", value)
  end)

  it("joins siblings after an exception and preserves input error order", function()
    local finished = false
    local value, err = Task.all({
      Task.new(function()
        async.sleep(20)
        return nil, "first"
      end),
      Task.new(function()
        error("second")
      end),
      Task.new(function()
        async.sleep(30)
        finished = true
      end),
    })
      :run()
      :wait(1000)
    assert.is_nil(value)
    assert.are.equal("first", err)
    assert.is_true(finished)
  end)

  it("keeps nil slots and domain failures as ordinary results", function()
    local values = Task.all({ Task.of(nil), Task.of(false), Task.of({ kind = "unknown" }) }):run():wait(1000)
    assert.are.equal(3, values.n)
    assert.is_nil(values[1])
    assert.is_false(values[2])
    assert.are.same({ kind = "unknown" }, values[3])
    assert.are.same({ n = 0 }, Task.all({}):run():wait(1000))
  end)
end)

describe("Task execution combinators", function()
  it("bounds concurrency and releases a permit after an exception", function()
    local limit = async.semaphore(1)
    local active, peak, calls = 0, 0, 0
    local tasks = {}
    for i = 1, 3 do
      tasks[i] = Task.new(function()
        calls = calls + 1
        active = active + 1
        peak = math.max(peak, active)
        async.sleep(5)
        active = active - 1
        if i == 1 then
          error("boom")
        end
        return i
      end):limited(limit)
    end
    local _, err = Task.all(tasks):run():wait(1000)
    assert.truthy(tostring(err):find("boom", 1, true))
    assert.are.equal(3, calls)
    assert.are.equal(1, peak)
  end)

  it("makes timing's inclusion of semaphore wait explicit and preserves false", function()
    local clock = 0
    local now = function()
      return clock
    end
    local limit = {
      with = function(_, fn)
        clock = clock + 10000000
        return fn()
      end,
    }
    local task = Task.new(function()
      clock = clock + 3000000
      return false
    end)
    assert.are.same({ value = false, ms = 13 }, task:limited(limit):timed(now):run():wait(1000))
    assert.are.same({ value = false, ms = 3 }, task:timed(now):limited(limit):run():wait(1000))
    local value, err = Task.fail(false):timed(now):run():wait(1000)
    assert.is_nil(value)
    assert.is_false(err)
  end)

  it(
    "tick hops to the next main-loop turn even from the main loop, so a scheduled callback runs between two synchronous steps",
    function()
      local order = {}
      local work = Task.of(1)
        :map(function(n)
          order[#order + 1] = "first"
          vim.schedule(function()
            order[#order + 1] = "scheduled"
          end)
          return n + 1
        end)
        :tick()
        :map(function(n)
          order[#order + 1] = "second"
          return n + 1
        end)
      local value
      work:run():on_complete(function(_, v)
        value = v
      end)
      assert.is_true(vim.wait(500, function()
        return value ~= nil
      end))
      assert.equals(3, value)
      assert.same({ "first", "scheduled", "second" }, order)
    end
  )
end)
