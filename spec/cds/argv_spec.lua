local argv = require("cds.argv")

describe("cds.argv", function()
  describe("a value", function()
    it("runs its steps in order and renders text", function()
      local title = argv.value("title"):map(vim.trim):map(string.upper)
      assert.are.equal("STANDUP", title:render("  Standup "))
    end)

    it("stops at the first guard that fails, with that guard's message", function()
      local name = argv
        .value("calendar")
        :guard(argv.is_text, "calendar must be text")
        :guard(argv.not_blank, "calendar is empty")
        :guard(argv.max_bytes(4), function(v)
          return ("calendar is too long (%d bytes)"):format(#v)
        end)
      assert.are.equal("Work", name:render("Work"))
      assert.are.same({ nil, "calendar must be text" }, { name:render(42) })
      assert.are.same({ nil, "calendar is empty" }, { name:render("  ") })
      assert.are.same({ nil, "calendar is too long (5 bytes)" }, { name:render("Works") })
    end)

    it("parses with a function that returns text, or names the value it refused", function()
      local month = argv.value("start month"):parse(argv.integer(1, 12))
      assert.are.equal("9", month:render(9))
      assert.are.same({ nil, "invalid start month: 13" }, { month:render(13) })
      assert.are.same({ nil, "invalid start month: 1.5" }, { month:render(1.5) })
      assert.are.same({ nil, "invalid start month: 9; do shell script" }, { month:render("9; do shell script") })
      assert.are.same({ nil, "invalid start month: nil" }, { month:render(nil) })
    end)

    it("renders a boolean as true or false and refuses anything else", function()
      local flag = argv.value("all_day"):parse(argv.boolean)
      assert.are.same({ "true", "false" }, { flag:render(true), flag:render(false) })
      assert.are.same({ nil, "invalid all_day: yes" }, { flag:render("yes") })
    end)

    it("offers the guards and maps text usually needs", function()
      assert.is_true(argv.printable("café ☕ -e --"))
      assert.is_false(argv.printable("a\nb"))
      assert.is_false(argv.printable("a\0b"))
      assert.are.equal("a b c d ", argv.spaces_for_control("a\0b\nc\td\127"))
      assert.is_true(argv.printable_lines("- a\n\t- b"))
      assert.is_false(argv.printable_lines("a\0b"))
      assert.are.equal("a\nb c", argv.spaces_for_control_except_lines("a\nb\0c"))
    end)

    -- argv entries are C strings: a value with an embedded NUL would arrive
    -- cut short at it, with no error.
    it("never renders a NUL byte, whatever the steps allowed", function()
      local careless = argv.value("title")
      assert.are.same({ nil, "title contains a NUL byte" }, { careless:render("nul\0byte") })
    end)

    it("refuses a value whose steps did not end in text", function()
      local careless = argv.value("count")
      assert.are.same({ nil, "count did not render as text" }, { careless:render(3) })
    end)

    it("is immutable: a step returns a new value and leaves the original alone", function()
      local base = argv.value("title")
      local upper = base:map(string.upper)
      assert.are.equal("x", base:render("x"))
      assert.are.equal("X", upper:render("x"))
    end)
  end)

  describe("positional", function()
    local values = argv.positional({
      argv.value("calendar"):guard(argv.not_blank, "no calendar"),
      argv.value("title"):map(vim.trim):guard(argv.not_blank, "no title"),
      argv.value("year"):parse(argv.integer(1, 9999)),
    })

    it("renders every value in order", function()
      assert.are.same({ "Work", "Standup", "2026" }, values:render({ "Work", " Standup ", 2026 }))
    end)

    it("returns the first failure and no partial list", function()
      assert.are.same({ nil, "no title" }, { values:render({ "Work", "  ", 0 }) })
      assert.are.same({ nil, "invalid year: 0" }, { values:render({ "Work", "x", 0 }) })
    end)

    it("refuses a list of the wrong length", function()
      assert.are.same({ nil, "expected 3 values, got 2" }, { values:render({ "Work", "x" }) })
    end)
  end)

  -- bpaf's strict positionals: values are only ever placed after "--", so
  -- none of them can be read as an option, whatever it begins with.
  describe("command", function()
    it("puts -- between the fixed part and the values", function()
      assert.are.same(
        { "osascript", "-e", "SCRIPT", "--", "-e", "--", "-Work" },
        argv.command({ "osascript", "-e", "SCRIPT" }, { "-e", "--", "-Work" })
      )
    end)

    it("leaves its inputs untouched", function()
      local fixed, values = { "tool" }, { "a" }
      argv.command(fixed, values)
      assert.are.same({ { "tool" }, { "a" } }, { fixed, values })
    end)
  end)
end)

describe("positional builder ownership", function()
  it("does not change when the caller extends its values array", function()
    local values = { argv.value("first"):map(tostring) }
    local renderer = argv.positional(values)
    values[2] = argv.value("second"):map(tostring)
    assert.are.same({ "one" }, renderer:render({ "one" }))
  end)
end)
