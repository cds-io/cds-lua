local module = require("cds.module")

describe("cds.module", function()
  local M = module("probe", {
    here = function()
      return "here"
    end,
  })

  it("leaves the module's own names alone", function()
    assert.are.equal("here", M.here())
    assert.are.equal("function", type(rawget(M, "here")))
  end)

  it("answers an unknown name with a function that fails at the call, in words", function()
    local ok, err = pcall(function()
      return M.gone(1, 2)
    end)
    assert.is_false(ok)
    assert.is_truthy(
      tostring(err):find(
        'cds.probe has no "gone": the cds-lua installed is older than this code needs, or the name is misspelt',
        1,
        true
      ),
      tostring(err)
    )
  end)

  it("knows the fallbacks it handed out, and nothing else", function()
    assert.is_true(module.is_fallback(M.gone))
    assert.is_false(module.is_fallback(M.here))
    assert.is_false(module.is_fallback(nil))
  end)

  it("holds nothing under the unknown name, so rawget and pairs see only what is there", function()
    assert.is_nil(rawget(M, "gone"))
    local keys = {}
    for key in pairs(M) do
      keys[#keys + 1] = key
    end
    assert.are.same({ "here" }, keys)
  end)

  it("names a method a Task instance does not have, through the class table", function()
    local Task = require("cds.task")
    local t = Task.of(1)
    local ok, err = pcall(function()
      return t:bend()
    end)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('cds.task has no "bend"', 1, true), tostring(err))
  end)
end)
