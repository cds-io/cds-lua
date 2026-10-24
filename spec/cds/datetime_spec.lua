local dt = require("cds.datetime")

--- Zeller's congruence: ISO weekday from the date alone, no os.time involved.
local function zeller(y, m, d)
  if m < 3 then
    y, m = y - 1, m + 12
  end
  local k, j = y % 100, math.floor(y / 100)
  local h = (d + math.floor(13 * (m + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) + 5 * j) % 7
  -- h: 0 is Saturday; ISO: 1 is Monday.
  return ((h + 5) % 7) + 1
end

--- Runs `fn` with $TZ set in this process (os.time and os.date follow it here).
local function in_zone(zone, fn)
  local before = vim.env.TZ
  vim.env.TZ = zone
  local ok, err = pcall(fn)
  vim.env.TZ = before
  assert(ok, err)
end

describe("cds.datetime", function()
  it("knows the days in a month, leap years included", function()
    assert.are.same({ 31, 28, 29, 28, 29 }, {
      dt.days_in_month(2026, 1),
      dt.days_in_month(2026, 2),
      dt.days_in_month(2028, 2),
      dt.days_in_month(2100, 2),
      dt.days_in_month(2000, 2),
    })
    assert.is_true(dt.is_valid(2026, 2, 28))
    assert.is_false(dt.is_valid(2026, 2, 30))
    assert.is_false(dt.is_valid(2026, 13, 1))
    assert.is_false(dt.is_valid(2026, 9, 31))
    assert.is_false(dt.is_valid(2026, 1.5, 1))
    assert.is_false(dt.is_valid("2026", 1, 1))
    -- os.time cannot represent every year; the note's range is bounded.
    assert.is_false(dt.is_valid(1899, 12, 31))
    assert.is_false(dt.is_valid(10000, 1, 1))
    assert.is_true(dt.is_valid(1900, 1, 1))
  end)

  it("adds days and keeps the time of day", function()
    local d = { year = 2026, month = 10, day = 4, hour = 15, min = 30 }
    assert.are.same({ year = 2026, month = 10, day = 7, hour = 15, min = 30 }, dt.add_days(d, 3))
    assert.are.same({ year = 2026, month = 9, day = 30, hour = 15, min = 30 }, dt.add_days(d, -4))
    assert.are.same({ year = 2027, month = 1, day = 1 }, dt.add_days({ year = 2026, month = 12, day = 31 }, 1))
    assert.are.same({ year = 2028, month = 2, day = 29 }, dt.add_days({ year = 2028, month = 2, day = 28 }, 1))
  end)

  -- The reason for noon: in Chile the clocks go forward at midnight on
  -- 2026-09-06, so 00:00 that day does not exist and mktime moves it.
  it("crosses a midnight daylight-saving switch without losing a day", function()
    for _, zone in ipairs({ "America/Santiago", "America/New_York", "Pacific/Auckland" }) do
      in_zone(zone, function()
        local sep5 = { year = 2026, month = 9, day = 5 }
        assert.are.same({ year = 2026, month = 9, day = 6 }, dt.add_days(sep5, 1), zone)
        assert.are.same({ year = 2026, month = 9, day = 7 }, dt.add_days(sep5, 2), zone)
        assert.are.equal(7, dt.weekday({ year = 2026, month = 9, day = 6 }), zone) -- a Sunday
      end)
    end
  end)

  it("agrees with Zeller's congruence on the weekday of a few thousand dates", function()
    for _, zone in ipairs({ "America/Santiago", "UTC" }) do
      in_zone(zone, function()
        local seed = 20260930
        local d = { year = 1990, month = 1, day = 1 }
        for _ = 1, 2500 do
          seed = (seed * 48271) % 2147483647 -- Park-Miller; the product stays under 2^53
          d = dt.add_days(d, seed % 40)
          assert.are.equal(
            zeller(d.year, d.month, d.day),
            dt.weekday(d),
            ("%s %d-%d-%d"):format(zone, d.year, d.month, d.day)
          )
        end
        assert.truthy(d.year > 2100)
      end)
    end
  end)

  it("finds the week's start and the next weekday from any day of the week", function()
    -- 2026-10-04 is a Sunday; the week around it runs Mon Sep 28 to Sun Oct 4.
    for day = 28, 34 do
      local d = day <= 30 and { year = 2026, month = 9, day = day } or { year = 2026, month = 10, day = day - 30 }
      assert.are.same({ year = 2026, month = 9, day = 28 }, dt.start_of_week(d, "monday"))
      if dt.weekday(d) == 7 then
        assert.are.same({ year = 2026, month = 10, day = 4 }, dt.start_of_week(d, "sunday"))
      else
        assert.are.same({ year = 2026, month = 9, day = 27 }, dt.start_of_week(d, "sunday"))
      end
      local next_monday = dt.next_weekday(d, 1)
      assert.are.equal(1, dt.weekday(next_monday))
      assert.are.equal(1, dt.compare(next_monday, d))
      assert.truthy(dt.to_time(next_monday) - dt.to_time(d) <= 7 * 86400)
    end
    -- Asked on a Monday, the next Monday is a week away, never today.
    assert.are.same({ year = 2026, month = 10, day = 5 }, dt.next_weekday({ year = 2026, month = 9, day = 28 }, 1))
  end)

  it("compares dates, then times, with a missing time as midnight", function()
    assert.are.equal(-1, dt.compare({ year = 2026, month = 1, day = 1 }, { year = 2026, month = 1, day = 2 }))
    assert.are.equal(
      0,
      dt.compare({ year = 2026, month = 1, day = 1 }, { year = 2026, month = 1, day = 1, hour = 0, min = 0 })
    )
    assert.are.equal(
      1,
      dt.compare({ year = 2026, month = 1, day = 1, hour = 9 }, { year = 2026, month = 1, day = 1, hour = 8, min = 59 })
    )
  end)

  describe("LDML", function()
    it("formats and parses each token", function()
      local d = { year = 2026, month = 3, day = 7, hour = 15, min = 5 }
      local cases = {
        { "yyyy-MM-dd", "2026-03-07" },
        { "M/d", "3/7" },
        { "d.M.yyyy", "7.3.2026" },
        { "dd/MM/yy", "07/03/26" },
        { "HH:mm", "15:05" },
        { "H:mm", "15:05" },
        { "h:mm a", "3:05 PM" },
        { "hh a", "03 PM" },
      }
      for _, case in ipairs(cases) do
        assert.are.equal(case[2], dt.format(d, case[1]), case[1])
        local back = dt.parse(case[2], case[1])
        for field, value in pairs(back) do
          assert.are.equal(d[field], value, case[1] .. " " .. field)
        end
      end
      assert.are.same({ hour = 0, min = 30 }, dt.parse("12:30 am", "h:mm a"))
      assert.are.same({ hour = 12, min = 0 }, dt.parse("12:00 pm", "h:mm a"))
      assert.are.same({ year = 1999 }, dt.parse("99", "yy"))
    end)

    it("matches the whole text and nothing else", function()
      assert.is_nil(dt.parse("2026-03-07x", "yyyy-MM-dd"))
      assert.is_nil(dt.parse("3/7/2026", "M/d"))
      assert.is_nil(dt.parse("13:00 pm", "h:mm a"))
      assert.is_nil(dt.parse("", "M/d"))
    end)

    it("refuses an unknown token when compiled, naming it", function()
      local compiled, err = dt.compile("yyyy-QQ-dd")
      assert.is_nil(compiled)
      assert.are.equal('unknown token "QQ" in format "yyyy-QQ-dd"', err)
      assert.truthy(dt.compile("M/d"))
    end)

    it("parses fields only; validity is is_valid's job", function()
      local parsed = dt.parse("2026-02-30", "yyyy-MM-dd")
      assert.are.same({ year = 2026, month = 2, day = 30 }, parsed)
      assert.is_false(dt.is_valid(parsed.year, parsed.month, parsed.day))
    end)
  end)
end)

describe("nullable date validation", function()
  it("returns false for a missing year, month, or day", function()
    local datetime = require("cds.datetime")
    assert.is_false(datetime.is_valid(nil, 10, 1))
    assert.is_false(datetime.is_valid(2026, nil, 1))
    assert.is_false(datetime.is_valid(2026, 10, nil))
  end)
end)
