local command = require("cds.command")
local notify, messages
before_each(function()
  notify, messages = vim.notify, {}
  vim.notify = function(message)
    messages[#messages + 1] = message
  end
end)
after_each(function()
  vim.notify = notify
  pcall(vim.api.nvim_del_user_command, "CdsExample")
  pcall(vim.keymap.del, "n", "<F21>")
  pcall(vim.keymap.del, "n", "<F22>")
end)

describe("cds.command", function()
  it("composes read, run and presentation including false results", function()
    local seen
    command.register({
      {
        name = "CdsExample",
        nargs = "?",
        read = function(args)
          return args.args
        end,
        run = function(input)
          assert.equal("input", input)
          return false
        end,
        present = function(value, input)
          seen = { value, input }
        end,
      },
    })
    vim.cmd("CdsExample input")
    assert.same({ false, "input" }, seen)
    assert.same({}, messages)
  end)

  it("accepts actions returning nothing", function()
    local calls = 0
    command.register({ {
      name = "CdsExample",
      run = function()
        calls = calls + 1
      end,
    } })
    vim.cmd.CdsExample()
    assert.equal(1, calls)
    assert.same({}, messages)
  end)

  it("reports read errors without running or presenting", function()
    command.register({
      {
        name = "CdsExample",
        read = function()
          return nil, "invalid input"
        end,
        run = function()
          error("must not run")
        end,
      },
    })
    vim.cmd.CdsExample()
    assert.same({ "invalid input" }, messages)
  end)

  it("reports work errors, raised exceptions, and presentation failures once", function()
    for _, spec in ipairs({
      {
        run = function()
          return nil, { message = "refused" }
        end,
      },
      {
        run = function()
          error("raised")
        end,
      },
      {
        run = function()
          return 1
        end,
        present = function()
          error("cannot draw")
        end,
      },
    }) do
      spec.name = "CdsExample"
      command.register({ spec })
      vim.cmd.CdsExample()
    end
    assert.equal(3, #messages)
    assert.equal("refused", messages[1])
    assert.matches("raised", messages[2])
    assert.matches("cannot draw", messages[3])
  end)

  it("captures independent inputs before async work yields", function()
    local results = {}
    command.register({
      {
        name = "CdsExample",
        nargs = 1,
        async = true,
        read = function(args)
          return args.args
        end,
        run = function(input)
          require("cds.async").await(1, function(done)
            vim.defer_fn(done, 10)
          end)
          return input
        end,
        present = function(value)
          results[#results + 1] = value
        end,
      },
    })
    vim.cmd("CdsExample one")
    vim.cmd("CdsExample two")
    assert.is_true(vim.wait(500, function()
      return #results == 2
    end))
    table.sort(results)
    assert.same({ "one", "two" }, results)
    assert.same({}, messages)
  end)

  it("re-registers commands and removes only its own obsolete key mappings", function()
    local calls = 0
    command.register({ { name = "CdsExample", keys = { "<F21>", "<F22>" }, run = function() end } })
    vim.keymap.set("n", "<F22>", "user mapping")
    command.register({ {
      name = "CdsExample",
      run = function()
        calls = calls + 1
      end,
    } })
    assert.same({}, vim.fn.maparg("<F21>", "n", false, true))
    assert.equal("user mapping", vim.fn.maparg("<F22>", "n", false, true).rhs)
    vim.cmd.CdsExample()
    assert.equal(1, calls)
  end)
  it("reports async failures once and skips presentation", function()
    command.register({
      {
        name = "CdsExample",
        async = true,
        run = function()
          return nil, "async refusal"
        end,
        present = function()
          error("must not present")
        end,
      },
    })
    vim.cmd.CdsExample()
    assert.is_true(vim.wait(500, function()
      return #messages == 1
    end))
    assert.same({ "async refusal" }, messages)
  end)
  it("routes failures to the caller's notifier", function()
    local reported
    command.register({
      {
        name = "CdsExample",
        run = function()
          return nil, "refused"
        end,
        notify = function(message, level)
          reported = { message, level }
        end,
      },
    })
    vim.cmd.CdsExample()
    assert.same({ "refused", vim.log.levels.ERROR }, reported)
    assert.same({}, messages)
  end)
end)
