local async = require("cds.async")
local fakeproc = require("fakeproc")
local secrets = require("cds.secrets")

describe("cds.secrets", function()
  after_each(fakeproc.uninstall)

  local function call(fn, ...)
    local args = { ... }
    return async
      .run(function()
        return fn(unpack(args))
      end)
      :wait(1000)
  end

  it("rejects an unknown backend and a missing service", function()
    local store, err = secrets.open({ backend = "nope", service = "calplus" })
    assert.is_nil(store)
    assert.are.equal('unknown secret backend "nope"', err)
    store, err = secrets.open({ backend = "op", vault = "Private" })
    assert.is_nil(store)
    assert.are.equal("secrets.open needs a service name", err)
  end)

  describe("os-key-store", function()
    local function open()
      return assert(secrets.open({ backend = "os-key-store", service = "calplus", platform = "OSX" }))
    end

    it("refuses a platform without a backend", function()
      local store, err = secrets.open({ backend = "os-key-store", service = "calplus", platform = "Linux" })
      assert.is_nil(store)
      assert.truthy(err:match("^no OS key store backend on this platform"))
    end)

    it("sets through `security -i` with the value as hex on stdin", function()
      fakeproc.install({ { match = "security -i", result = { code = 0 } } })
      assert.is_true(call(open().set, "google", '{"t":"sekrit"}'))
      assert.are.same({ "security", "-i" }, fakeproc.calls[1].argv)
      assert.are.equal(
        "add-generic-password -a google -s calplus -U -X 7b2274223a2273656b726974227d\n",
        fakeproc.calls[1].stdin
      )
      assert.falsy(fakeproc.all_argv():find("sekrit", 1, true))
    end)

    it("gets the value and strips the trailing newline", function()
      fakeproc.install({ { match = "find-generic-password", result = { code = 0, stdout = "sekrit\n" } } })
      assert.are.equal("sekrit", call(open().get, "google"))
      assert.are.same(
        { "security", "find-generic-password", "-a", "google", "-s", "calplus", "-w" },
        fakeproc.calls[1].argv
      )
    end)

    it("reads exit 44 as absent and any other failure as an error", function()
      fakeproc.install({ { match = "find-generic-password", result = { code = 44, stderr = "not found" } } })
      local value, err = call(open().get, "google")
      assert.is_nil(value)
      assert.is_nil(err)
      fakeproc.install({ { match = "find-generic-password", result = { code = 36, stderr = "locked" } } })
      value, err = call(open().get, "google")
      assert.is_nil(value)
      assert.are.equal("security exit 36: locked", err)
    end)

    it("deletes, treating an absent item as success", function()
      fakeproc.install({ { match = "delete-generic-password", result = { code = 44 } } })
      assert.is_true(call(open().delete, "google"))
      fakeproc.install({ { match = "delete-generic-password", result = { code = 1, stderr = "nope" } } })
      local ok, err = call(open().delete, "google")
      assert.is_nil(ok)
      assert.are.equal("security exit 1: nope", err)
    end)
  end)

  describe("op", function()
    local absent = '[ERROR] 2026/09/29 19:39:01 "calplus-google" isn\'t an item in the "Private" vault.'

    local function open()
      return assert(secrets.open({ backend = "op", service = "calplus", vault = "Private" }))
    end

    it("requires a vault", function()
      local store, err = secrets.open({ backend = "op", service = "calplus" })
      assert.is_nil(store)
      assert.truthy(err:match("^the op backend needs a vault"))
    end)

    it("gets through `op read` and reads the absent message as nil, nil", function()
      fakeproc.install({ { match = "op read", result = { code = 0, stdout = "sekrit" } } })
      assert.are.equal("sekrit", call(open().get, "google"))
      assert.are.same({ "op", "read", "--no-newline", "op://Private/calplus-google/password" }, fakeproc.calls[1].argv)
      fakeproc.install({ { match = "op read", result = { code = 1, stderr = absent } } })
      local value, err = call(open().get, "google")
      assert.is_nil(value)
      assert.is_nil(err)
    end)

    it("reports any other failure with op's message, timestamp stripped", function()
      fakeproc.install({
        { match = "op read", result = { code = 1, stderr = "[ERROR] 2026/09/29 19:39:01 account is not signed in" } },
      })
      local value, err = call(open().get, "google")
      assert.is_nil(value)
      assert.are.equal("op exit 1: account is not signed in", err)
    end)

    it("edits first with the template on stdin, and never puts the value on argv", function()
      fakeproc.install({ { match = "op item edit", result = { code = 0 } } })
      assert.is_true(call(open().set, "google", "sekrit"))
      assert.are.same({ "op", "item", "edit", "calplus-google", "--vault", "Private", "-" }, fakeproc.calls[1].argv)
      local item = vim.json.decode(fakeproc.calls[1].stdin)
      assert.are.same({ "calplus-google", "PASSWORD", "sekrit" }, { item.title, item.category, item.fields[1].value })
      assert.falsy(fakeproc.all_argv():find("sekrit", 1, true))
    end)

    it("creates only when the edit reports the item absent", function()
      fakeproc.install({
        {
          match = "op item edit",
          result = {
            code = 1,
            stderr = "[ERROR] 2026/09/29 19:39:01 unable to process line 1: could not find item to edit",
          },
        },
        { match = "op item create", result = { code = 0 } },
      })
      assert.is_true(call(open().set, "google", "sekrit"))
      assert.are.same({ "op", "item", "create", "--vault", "Private", "-" }, fakeproc.calls[2].argv)
      assert.are.equal(fakeproc.calls[1].stdin, fakeproc.calls[2].stdin)
      fakeproc.install({
        {
          match = "op item edit",
          result = { code = 1, stderr = "[ERROR] 2026/09/29 19:39:01 More than one item matches" },
        },
      })
      local ok, err = call(open().set, "google", "sekrit")
      assert.is_nil(ok)
      assert.are.equal("op exit 1: More than one item matches", err)
    end)

    it("deletes, treating an absent item as success", function()
      fakeproc.install({ { match = "op item delete", result = { code = 1, stderr = absent } } })
      assert.is_true(call(open().delete, "google"))
      assert.are.same({ "op", "item", "delete", "calplus-google", "--vault", "Private" }, fakeproc.calls[1].argv)
    end)
  end)
end)
