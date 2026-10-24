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

    it("names what is not there; a table or a value under the name counts as there", function()
      assert.are.same({ "probe.gone" }, needs.missing({ probe = { "here", "gone", "value" } }))
    end)

    it("counts every function of a module that does not load", function()
      assert.are.same({ "absent.a", "absent.b" }, needs.missing({ absent = { "a", "b" } }))
    end)

    it("lists modules in name order, each in declaration order", function()
      assert.are.same({ "absent.z", "probe.gone" }, needs.missing({ probe = { "here", "gone" }, absent = { "z" } }))
    end)
  end)

  describe("missing, against a module that answers every name", function()
    it("still reports what the module itself does not hold", function()
      package.preload["cds.wrapped"] = function()
        return require("cds.module")("wrapped", { here = function() end })
      end
      assert.are.same({ "wrapped.gone" }, needs.missing({ wrapped = { "here", "gone" } }))
      package.preload["cds.wrapped"], package.loaded["cds.wrapped"] = nil, nil
    end)

    it("counts a name a module answers through a metatable of its own, as vim.async does", function()
      package.preload["cds.lazyish"] = function()
        return setmetatable({}, {
          __index = function(_, key)
            if key == "here" then
              return function() end
            end
          end,
        })
      end
      assert.are.same({ "lazyish.gone" }, needs.missing({ lazyish = { "here", "gone" } }))
      needs.strict("a.nvim", { lazyish = { "here" } })
      assert.are.equal("function", type(require("cds.lazyish").here))
      package.preload["cds.lazyish"], package.loaded["cds.lazyish"] = nil, nil
    end)
  end)

  describe("check", function()
    it("is nil when nothing is missing", function()
      assert.is_nil(needs.check("a.nvim", { probe = { "here" } }))
    end)

    it("is one sentence naming the plugin, the functions and the remedy", function()
      assert.are.equal(
        "a.nvim needs cds-lua with probe.gone, probe.nope: "
          .. "install cds-io/cds-lua at the commit lazy.lua pins, or update it",
        needs.check("a.nvim", { probe = { "gone", "nope" } })
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

    it("lets the library's own files through, loaded after the proxies went in", function()
      -- a module compiled as if it were lua/cds/late.lua, reaching an
      -- undeclared name of a proxied module from inside the library
      package.preload["cds.late"] = assert(load(
        [[
          local probe = require("cds.probe")
          return { go = function() probe.also() return "late" end }
        ]],
        "@lua/cds/late.lua"
      ))
      needs.strict("a.nvim", { probe = { "here" } })
      assert.are.equal("late", require("cds.late").go())
      package.preload["cds.late"], package.loaded["cds.late"] = nil, nil
    end)

    it("reads a declared name from the real module, so a check under strict sees what is there", function()
      needs.strict("a.nvim", { probe = { "here", "gone" } })
      assert.are.same({}, needs.missing({ probe = { "here" } }))
      assert.are.same({ "probe.gone" }, needs.missing({ probe = { "here", "gone" } }))
    end)

    it("reads a seam a spec replaced on the real module, through the proxy", function()
      local real = require("cds.probe")
      needs.strict("a.nvim", { probe = { "here" } })
      local replaced = function()
        return "replaced"
      end
      require("cds.probe").here = replaced
      assert.are.equal(replaced, real.here)
      assert.are.equal("replaced", require("cds.probe").here())
    end)

    it("passes a write through to the real module, a hook being set rather than a name read", function()
      local real = require("cds.probe")
      needs.strict("a.nvim", { probe = { "here" } })
      require("cds.probe").hook = "set"
      assert.are.equal("set", real.hook)
      assert.is_nil(rawget(require("cds.probe"), "hook"))
    end)

    it("leaves a module the tier cannot load alone", function()
      package.preload["cds.needsvim"] = function()
        error("attempt to index global 'vim'")
      end
      assert.has_no.errors(function()
        needs.strict("a.nvim", { probe = { "here" }, needsvim = { "x" } })
      end)
      -- no proxy went in: what require leaves behind a failed load is its
      -- own sentinel, never a table
      assert.are_not.equal("table", type(package.loaded["cds.needsvim"]))
      package.preload["cds.needsvim"], package.loaded["cds.needsvim"] = nil, nil
    end)
  end)
end)
