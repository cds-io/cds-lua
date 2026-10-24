local async = require("cds.async")

describe("cds.async", function()
  it("is vim.async", function()
    assert.are.equal(vim.async, async)
  end)

  it("runs a task and returns its result through wait", function()
    local task = async.run(function()
      async.sleep(1)
      return 42
    end)
    assert.are.equal(42, task:wait(1000))
  end)

  it("limits concurrency with a semaphore", function()
    local limit, running, peak = async.semaphore(2), 0, 0
    local task = async.run(function()
      local tasks = {}
      for i = 1, 5 do
        tasks[i] = async.run(function()
          return limit:with(function()
            running = running + 1
            peak = math.max(peak, running)
            async.sleep(5)
            running = running - 1
          end)
        end)
      end
      for _, t in ipairs(tasks) do
        async.await(t)
      end
    end)
    task:wait(1000)
    assert.are.equal(2, peak)
  end)
end)
