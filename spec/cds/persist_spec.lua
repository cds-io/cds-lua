local persist = require("cds.persist")
local root
before_each(function()
  root = vim.fn.tempname()
end)
after_each(function()
  vim.fn.delete(root, "rf")
end)

describe("cds.persist", function()
  it("round trips text exactly and creates parent directories", function()
    local path = root .. "/nested/state"
    assert(persist.write(path, "a\n\0b\n"))
    assert.equal("a\n\0b\n", persist.read(path))
    assert(persist.write(path, ""))
    assert.equal("", persist.read(path))
  end)

  it("round trips JSON values including false", function()
    local path = root .. "/state.json"
    assert(persist.save_json(path, { labels = { "one", "two" } }))
    assert.same({ labels = { "one", "two" } }, persist.load_json(path))
    assert(persist.save_json(path, false))
    local value, err = persist.load_json(path)
    assert.is_false(value)
    assert.is_nil(err)
  end)

  it("keeps the previous value on encoding failure", function()
    local path = root .. "/state.json"
    assert(persist.save_json(path, { saved = true }))
    local cyclic = {}
    cyclic.self = cyclic
    local ok, err = persist.save_json(path, cyclic)
    assert.is_nil(ok)
    assert.matches("encode JSON", err)
    assert.same({ saved = true }, persist.load_json(path))
  end)

  it("reports missing and malformed files with their paths", function()
    local path = root .. "/missing.json"
    local value, err = persist.load_json(path)
    assert.is_nil(value)
    assert.truthy(err:find(path, 1, true))
    assert(persist.write(path, "not JSON"))
    value, err = persist.load_json(path)
    assert.is_nil(value)
    assert.matches("parse JSON", err)
  end)

  it("cleans up temporary files after a rename refusal", function()
    vim.fn.mkdir(root .. "/directory", "p")
    local ok, err = persist.write(root .. "/directory", "content")
    assert.is_nil(ok)
    assert.is_string(err)
    assert.same({}, vim.fn.glob(root .. "/directory.*", false, true))
    assert.equal(1, vim.fn.isdirectory(root .. "/directory"))
  end)
end)
