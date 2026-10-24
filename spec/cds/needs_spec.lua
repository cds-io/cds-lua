local needs = require("cds.needs")

describe("cds.needs", function()
  before_each(function()
    package.preload["cds.probe"] = function()
      return {
        here = function() end,
        also = function() end,
        value = 1,
      }
    end
    -- a module that uses another internally, beyond what a plugin declares
    package.preload["cds.over"] = function()
      local probe = require("cds.probe")
      return {
        go = function()
          probe.also()
          return "went"
        end,
      }
    end
  end)

  after_each(function()
    for _, name in ipairs({ "cds.probe", "cds.over" }) do
      package.preload[name] = nil
      package.loaded[name] = nil
    end
  end)

  describe("missing", function()
    it("answers nothing when every declared function is there", function()
      assert.are.same({}, needs.missing({ probe = { "here", "also" } }))
    end)

    it("names a function that is not there, and a field that is not a function", function()
      assert.are.same({ "probe.gone", "probe.value" }, needs.missing({ probe = { "here", "gone", "value" } }))
    end)

    it("counts every function of a module that does not load", function()
      assert.are.same({ "absent.a", "absent.b" }, needs.missing({ absent = { "a", "b" } }))
    end)

    it("lists modules in name order, each in declaration order", function()
      assert.are.same({ "absent.z", "probe.gone" }, needs.missing({ probe = { "here", "gone" }, absent = { "z" } }))
    end)
  end)

  describe("check", function()
    it("is nil when nothing is missing", function()
      assert.is_nil(needs.check("a.nvim", { probe = { "here" } }))
    end)

    it("is one sentence naming the plugin, the functions and the remedy", function()
      assert.are.equal(
        "a.nvim needs cds-lua with probe.gone, probe.value: "
          .. "install cds-io/cds-lua at the commit lazy.lua pins, or update it",
        needs.check("a.nvim", { probe = { "gone", "value" } })
      )
    end)
  end)

  describe("strict", function()
    it("answers a declared function and raises on another, naming the plugin", function()
      needs.strict("a.nvim", { probe = { "here" } })
      local probe = require("cds.probe")
      assert.are.equal("function", type(probe.here))
      local ok, err = pcall(function()
        return probe.also
      end)
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("a.nvim uses cds.probe.also without declaring it in its needs", 1, true))
    end)

    it("leaves a module's own use of another module to the real one", function()
      needs.strict("a.nvim", { probe = { "here" }, over = { "go" } })
      assert.are.equal("went", require("cds.over").go())
    end)
  end)
end)
