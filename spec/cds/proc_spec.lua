local async = require("cds.async")
local proc = require("cds.proc")

-- The only spec that spawns real processes: sh and cat exist on every CI runner.
describe("cds.proc", function()
  local function run(...)
    local args = { ... }
    local task = async.run(function()
      return proc.run(unpack(args))
    end)
    return task:wait(5000)
  end

  it("returns a non-zero exit as data, with both streams", function()
    local r = run({ "sh", "-c", "echo out; echo err >&2; exit 28" })
    assert.are.same({ code = 28, stdout = "out\n", stderr = "err\n", timed_out = false }, {
      code = r.code,
      stdout = r.stdout,
      stderr = r.stderr,
      timed_out = r.timed_out,
    })
  end)

  it("passes stdin to the process", function()
    local r = run({ "cat" }, { stdin = "hello" })
    assert.are.equal("hello", r.stdout)
  end)

  -- vim.system's exit callback runs in a fast event context, where vim.env,
  -- vim.fn and most API calls raise E5560; callers must never land there.
  it("resumes the caller on the main loop, outside a fast event context", function()
    local task = async.run(function()
      proc.run({ "cat" }, { stdin = "x" })
      return vim.in_fast_event(), pcall(function()
        return vim.env.HOME ~= nil
      end)
    end)
    local fast, env_ok = task:wait(5000)
    assert.is_false(fast)
    assert.is_true(env_ok)
  end)

  it("returns nil and a message when the binary does not exist", function()
    local r, err = run({ "calplus-no-such-binary" })
    assert.is_nil(r)
    assert.truthy(err:match("^calplus%-no%-such%-binary: ENOENT"))
  end)

  it("marks a killed process as timed out", function()
    local r = run({ "sleep", "5" }, { timeout = 50 })
    assert.is_true(r.timed_out)
    assert.are.equal(124, r.code)
  end)
end)
