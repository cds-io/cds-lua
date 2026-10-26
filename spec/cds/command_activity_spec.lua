local command = require("cds.command")
local async = require("cds.async")
local activity, pending, results, messages, notify, win, previous

local function composed(tracker, spec, opts)
  return command.with_activity(tracker, opts or {
    kind = "fetch",
    label = function(input)
      return input.label
    end,
    window = function(input)
      return input.win
    end,
  }, spec)
end

local function register(tracker, run, opts)
  command.register({
    composed(tracker, {
      name = "CdsActivityExample",
      nargs = 1,
      read = function(args)
        return { label = args.args, win = win }
      end,
      run = run or function(input)
        async.await(1, function(done)
          pending[input.label] = done
        end)
        return input.label
      end,
      present = function(value, input)
        results[#results + 1] = { value, input.label }
      end,
    }, opts),
  })
end

local function settle(label)
  local done = pending[label]
  pending[label] = nil
  done()
  assert.is_true(vim.wait(500, function()
    return #results + #messages > 0
  end))
end

before_each(function()
  activity = require("cds.activity").new({ autocmd = "CdsTestActivity" })
  pending, results, messages = {}, {}, {}
  notify = vim.notify
  vim.notify = function(message)
    messages[#messages + 1] = message
  end
  win = vim.api.nvim_get_current_win()
  previous = vim.wo[win].statusline
  vim.wo[win].statusline = "original"
end)

after_each(function()
  for _, done in pairs(pending) do
    done()
  end
  vim.wait(20, function()
    return false
  end)
  activity:reset()
  vim.notify = notify
  pcall(vim.api.nvim_del_user_command, "CdsActivityExample")
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].statusline = previous
  end
  vim.cmd("silent! only!")
end)

describe("cds.command.with_activity", function()
  it("copies the spec without changing callbacks or mutating the original", function()
    local spec = {
      name = "CdsActivityExample",
      run = function()
        return false
      end,
    }
    local wrapped = composed(activity, spec)
    assert.is_true(wrapped.async)
    assert.is_nil(spec.async)
    assert.are_not.equal(spec.run, wrapped.run)
    assert.equal(spec.name, wrapped.name)
    local value, err = wrapped.run({ label = "one", win = win })
    assert.is_false(value)
    assert.is_nil(err)
    assert.is_false(activity:busy())
    assert.equal("original", vim.wo[win].statusline)
  end)

  it("returns immediately, captures inputs and restores feedback before presenting", function()
    register(activity)
    vim.cmd("CdsActivityExample one")
    assert.is_true(activity:busy())
    assert.same({}, results)
    assert.matches("activity_segment", vim.wo[win].statusline)
    assert.matches("fetch one", command.activity_segment(win))
    vim.cmd("new")
    local other = vim.api.nvim_get_current_win()
    settle("one")
    assert.same({ { "one", "one" } }, results)
    assert.equal(other, vim.api.nvim_get_current_win())
    assert.equal("original", vim.wo[win].statusline)
    assert.equal("", command.activity_segment(win))
    assert.is_false(activity:busy())
  end)

  it("finishes returned failures and exceptions and reports each only once", function()
    for _, run in ipairs({
      function()
        return nil, "refused"
      end,
      function()
        error("exploded")
      end,
    }) do
      messages = {}
      register(activity, run)
      vim.cmd("CdsActivityExample failure")
      assert.is_true(vim.wait(500, function()
        return #messages > 0
      end))
      assert.equal(1, #messages)
      assert.same({}, results)
      assert.is_false(activity:busy())
      assert.equal("original", vim.wo[win].statusline)
    end
  end)

  it("does not begin Activity when read refuses input", function()
    command.register({
      composed(activity, {
        name = "CdsActivityExample",
        read = function()
          return nil, "bad input"
        end,
        run = function()
          error("unexpected work")
        end,
      }),
    })
    vim.cmd.CdsActivityExample()
    assert.same({ "bad input" }, messages)
    assert.equal(0, activity.next_id)
  end)

  it("supports tracking without a window and actions returning nothing", function()
    register(activity, function() end, { kind = "refresh", label = "example" })
    vim.cmd("CdsActivityExample one")
    assert.is_true(vim.wait(500, function()
      return #results > 0
    end))
    assert.equal("original", vim.wo[win].statusline)
    assert.is_false(activity:busy())
    assert.same({}, messages)
  end)

  it("keeps feedback until overlapping runs using the same tracker finish", function()
    register(activity)
    vim.cmd("CdsActivityExample one")
    vim.cmd("CdsActivityExample two")
    settle("one")
    assert.is_true(activity:busy())
    assert.matches("fetch two", command.activity_segment(win))
    assert.is_nil(command.activity_segment(win):find("fetch one", 1, true))
    assert.matches("activity_segment", vim.wo[win].statusline)
    settle("two")
    assert.is_true(vim.wait(500, function()
      return #results == 2
    end))
    assert.is_false(activity:busy())
    assert.equal("original", vim.wo[win].statusline)
  end)

  it("shares window feedback across independent trackers", function()
    local other = require("cds.activity").new({ autocmd = "CdsOtherActivity" })
    register(activity)
    vim.cmd("CdsActivityExample one")
    register(other)
    vim.cmd("CdsActivityExample two")
    assert.matches("fetch one", command.activity_segment(win))
    assert.matches("fetch two", command.activity_segment(win))
    settle("one")
    assert.is_true(other:busy())
    assert.matches("fetch two", command.activity_segment(win))
    settle("two")
    assert.is_true(vim.wait(500, function()
      return not other:busy()
    end))
    assert.equal("original", vim.wo[win].statusline)
  end)

  it("preserves a statusline replaced by the user while work is pending", function()
    register(activity)
    vim.cmd("CdsActivityExample one")
    vim.wo[win].statusline = "replacement"
    settle("one")
    assert.equal("replacement", vim.wo[win].statusline)
    assert.is_false(activity:busy())
  end)

  it("finishes safely after the feedback window is closed", function()
    vim.cmd("new")
    win = vim.api.nvim_get_current_win()
    register(activity)
    vim.cmd("CdsActivityExample one")
    vim.api.nvim_win_close(win, true)
    settle("one")
    assert.is_false(activity:busy())
    assert.equal("", command.activity_segment(win))
    assert.same({}, messages)
  end)
end)
