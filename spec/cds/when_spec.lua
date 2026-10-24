local when = require("cds.when")

-- Sunday 2026-10-04, 15:00. The week around it: Mon Sep 28 to Sun Oct 4
-- with weeks starting Monday; Sun Oct 4 to Sat Oct 10 with weeks starting Sunday.
local NOW = { year = 2026, month = 10, day = 4, hour = 15, min = 0 }

local function ctx(over)
  return vim.tbl_extend(
    "force",
    { now = NOW, first_day_of_week = "monday", default_duration = 30, formats = {} },
    over or {}
  )
end

local function d(y, m, day, h, mi)
  if h then
    return { year = y, month = m, day = day, hour = h, min = mi }
  end
  return { year = y, month = m, day = day }
end

local function timed(y, m, day, h1, m1, h2, m2, tz)
  return { start = d(y, m, day, h1, m1), finish = d(y, m, day, h2, m2), all_day = false, tz = tz }
end

local function all_day(y1, m1, d1, y2, m2, d2)
  return { start = d(y1, m1, d1), finish = d(y2, m2, d2), all_day = true }
end

describe("cds.when", function()
  describe("dates", function()
    local cases = {
      { "today", all_day(2026, 10, 4, 2026, 10, 5) },
      { "tomorrow", all_day(2026, 10, 5, 2026, 10, 6) },
      { "yesterday", all_day(2026, 10, 3, 2026, 10, 4) },
      { "in 3 days", all_day(2026, 10, 7, 2026, 10, 8) },
      { "in 2 weeks", all_day(2026, 10, 18, 2026, 10, 19) },
      -- The coming one: on a Sunday, monday is tomorrow and sunday is a week away.
      { "monday", all_day(2026, 10, 5, 2026, 10, 6) },
      { "Mon", all_day(2026, 10, 5, 2026, 10, 6) },
      { "sunday", all_day(2026, 10, 11, 2026, 10, 12) },
      { "friday", all_day(2026, 10, 9, 2026, 10, 10) },
      -- this/next/last count weeks from first_day_of_week (Monday here).
      { "this monday", all_day(2026, 9, 28, 2026, 9, 29) },
      { "this friday", all_day(2026, 10, 2, 2026, 10, 3) },
      { "next monday", all_day(2026, 10, 5, 2026, 10, 6) },
      { "next friday", all_day(2026, 10, 9, 2026, 10, 10) },
      { "last monday", all_day(2026, 9, 21, 2026, 9, 22) },
      -- Month names, either order, with or without ordinal and year.
      { "oct 2", all_day(2027, 10, 2, 2027, 10, 3) }, -- already past this year
      { "oct 4", all_day(2026, 10, 4, 2026, 10, 5) }, -- today counts as not past
      { "2 dec", all_day(2026, 12, 2, 2026, 12, 3) },
      { "December 2nd", all_day(2026, 12, 2, 2026, 12, 3) },
      { "Dec 2nd, 2027", all_day(2027, 12, 2, 2027, 12, 3) },
      { "oct 2 2027", all_day(2027, 10, 2, 2027, 10, 3) },
      { "1st jan", all_day(2027, 1, 1, 2027, 1, 2) },
      { "feb 29", all_day(2028, 2, 29, 2028, 3, 1) }, -- the next leap year
      { "2026-10-02", all_day(2026, 10, 2, 2026, 10, 3) },
      -- Ranges, finish exclusive.
      { "oct 5-7", all_day(2026, 10, 5, 2026, 10, 8) },
      { "oct 5 - oct 7", all_day(2026, 10, 5, 2026, 10, 8) },
      { "mon-wed", all_day(2026, 10, 5, 2026, 10, 8) },
      { "dec 30 - jan 2", all_day(2026, 12, 30, 2027, 1, 3) },
      { "2026-10-05 to 2026-10-06", all_day(2026, 10, 5, 2026, 10, 7) },
    }
    for _, case in ipairs(cases) do
      it(("reads %q"):format(case[1]), function()
        local result, err = when.parse(case[1], ctx())
        assert.is_nil(err and err.message)
        assert.are.same(case[2], result)
      end)
    end

    it("counts next week from Sunday when weeks start on Sunday", function()
      -- Sun Oct 4 starts this week; next Monday is Oct 12, eight days out.
      assert.are.same(
        all_day(2026, 10, 12, 2026, 10, 13),
        (when.parse("next monday", ctx({ first_day_of_week = "sunday" })))
      )
      assert.are.same(
        all_day(2026, 10, 5, 2026, 10, 6),
        (when.parse("this monday", ctx({ first_day_of_week = "sunday" })))
      )
      assert.are.same(all_day(2026, 10, 5, 2026, 10, 6), (when.parse("monday", ctx({ first_day_of_week = "sunday" }))))
    end)

    it("reads numeric dates only through parse.formats", function()
      assert.is_nil((when.parse("10/6", ctx())))
      assert.are.same(all_day(2026, 10, 6, 2026, 10, 7), (when.parse("10/6", ctx({ formats = { "M/d" } }))))
      assert.are.same(all_day(2027, 6, 10, 2027, 6, 11), (when.parse("10/6", ctx({ formats = { "d/M" } }))))
      assert.are.same(all_day(2026, 10, 6, 2026, 10, 7), (when.parse("6.10.2026", ctx({ formats = { "d.M.yyyy" } }))))
      assert.are.same(timed(2026, 10, 6, 9, 0, 9, 30), (when.parse("10/6 9am", ctx({ formats = { "M/d" } }))))
    end)
  end)

  describe("times", function()
    local cases = {
      { "3pm", timed(2026, 10, 4, 15, 0, 15, 30) },
      { "9 AM", timed(2026, 10, 4, 9, 0, 9, 30) },
      { "9", timed(2026, 10, 4, 9, 0, 9, 30) },
      { "9:30", timed(2026, 10, 4, 9, 30, 10, 0) },
      { "0930", timed(2026, 10, 4, 9, 30, 10, 0) },
      { "14:00", timed(2026, 10, 4, 14, 0, 14, 30) },
      { "noon", timed(2026, 10, 4, 12, 0, 12, 30) },
      { "midnight", timed(2026, 10, 4, 0, 0, 0, 30) },
      { "12am", timed(2026, 10, 4, 0, 0, 0, 30) },
      { "12pm", timed(2026, 10, 4, 12, 0, 12, 30) },
      { "23:45", { start = d(2026, 10, 4, 23, 45), finish = d(2026, 10, 5, 0, 15), all_day = false } },
      -- note2cal's table.
      { "6-7", timed(2026, 10, 4, 6, 0, 7, 0) },
      { "3-430", timed(2026, 10, 4, 3, 0, 4, 30) },
      { "3p-4p", timed(2026, 10, 4, 15, 0, 16, 0) },
      { "3pm-4pm", timed(2026, 10, 4, 15, 0, 16, 0) },
      { "12pm-1pm", timed(2026, 10, 4, 12, 0, 13, 0) },
      { "12am-1am", timed(2026, 10, 4, 0, 0, 1, 0) },
      { "0500-1730", timed(2026, 10, 4, 5, 0, 17, 30) },
      { "3:15-4:30", timed(2026, 10, 4, 3, 15, 4, 30) },
      { "315a-430a", timed(2026, 10, 4, 3, 15, 4, 30) },
      { "315am-430am", timed(2026, 10, 4, 3, 15, 4, 30) },
      { "3:15am-4:30am", timed(2026, 10, 4, 3, 15, 4, 30) },
      -- A meridiem on one side carries to the other.
      { "3-4pm", timed(2026, 10, 4, 15, 0, 16, 0) },
      { "11-1pm", timed(2026, 10, 4, 11, 0, 13, 0) },
      { "3pm-4", timed(2026, 10, 4, 15, 0, 16, 0) },
      { "11am-1", timed(2026, 10, 4, 11, 0, 13, 0) },
      { "11-1", timed(2026, 10, 4, 11, 0, 13, 0) },
      { "9 to 10", timed(2026, 10, 4, 9, 0, 10, 0) },
      { "9:00 \226\128\147 9:30", timed(2026, 10, 4, 9, 0, 9, 30) }, -- an en dash, as an editor may type it
      -- Durations.
      { "3pm for 45m", timed(2026, 10, 4, 15, 0, 15, 45) },
      { "3pm for 1h", timed(2026, 10, 4, 15, 0, 16, 0) },
      { "3pm for 1h30", timed(2026, 10, 4, 15, 0, 16, 30) },
      { "3pm for 2 hours", timed(2026, 10, 4, 15, 0, 17, 0) },
      { "3pm for 90 minutes", timed(2026, 10, 4, 15, 0, 16, 30) },
      -- A named time counts as bare: noon-1 is lunch, not an overnight.
      { "noon-1", timed(2026, 10, 4, 12, 0, 13, 0) },
      { "noon-4", timed(2026, 10, 4, 12, 0, 16, 0) },
      { "noon to 1:30", timed(2026, 10, 4, 12, 0, 13, 30) },
      { "noon-12:30", timed(2026, 10, 4, 12, 0, 12, 30) },
      { "midnight-1", timed(2026, 10, 4, 0, 0, 1, 0) },
      { "12-12:30", timed(2026, 10, 4, 12, 0, 12, 30) },
      { "12-1", timed(2026, 10, 4, 12, 0, 13, 0) },
      -- A bare start past noon with a small end runs into the next day.
      { "22-2", { start = d(2026, 10, 4, 22, 0), finish = d(2026, 10, 5, 2, 0), all_day = false } },
      { "9pm-1am", { start = d(2026, 10, 4, 21, 0), finish = d(2026, 10, 5, 1, 0), all_day = false } },
      -- The carried meridiem flips only when that lands the end after the start on the same day.
      { "9am-1", timed(2026, 10, 4, 9, 0, 13, 0) },
    }
    for _, case in ipairs(cases) do
      it(("reads %q"):format(case[1]), function()
        local result, err = when.parse(case[1], ctx())
        assert.is_nil(err and err.message)
        assert.are.same(case[2], result)
      end)
    end

    it("takes the configured default duration", function()
      assert.are.same(timed(2026, 10, 4, 15, 0, 16, 0), (when.parse("3pm", ctx({ default_duration = 60 }))))
    end)
  end)

  describe("dates with times", function()
    local cases = {
      { "tomorrow 3pm", timed(2026, 10, 5, 15, 0, 15, 30) },
      { "tomorrow 9 AM ET", timed(2026, 10, 5, 9, 0, 9, 30, "America/New_York") },
      { "next friday 9-9:30 ET", timed(2026, 10, 9, 9, 0, 9, 30, "America/New_York") },
      { "oct 6 3pm-4pm", timed(2026, 10, 6, 15, 0, 16, 0) },
      { "2026-10-06 14:00", timed(2026, 10, 6, 14, 0, 14, 30) },
      { "monday noon for 1h", timed(2026, 10, 5, 12, 0, 13, 0) },
      { "oct 6 3pm - oct 7 10am", { start = d(2026, 10, 6, 15, 0), finish = d(2026, 10, 7, 10, 0), all_day = false } },
      { "oct 6 10pm - 2am", { start = d(2026, 10, 6, 22, 0), finish = d(2026, 10, 7, 2, 0), all_day = false } },
      { "3pm UTC", timed(2026, 10, 4, 15, 0, 15, 30, "UTC") },
      { "3pm pst", timed(2026, 10, 4, 15, 0, 15, 30, "America/Los_Angeles") },
      { "3pm Europe/Paris", timed(2026, 10, 4, 15, 0, 15, 30, "Europe/Paris") },
      -- A four-digit number after a month-name date is a year only when it can be one.
      { "oct 6 0930", timed(2026, 10, 6, 9, 30, 10, 0) },
      { "oct 6 1730", timed(2026, 10, 6, 17, 30, 18, 0) },
      { "6 oct 0930", timed(2026, 10, 6, 9, 30, 10, 0) },
      { "oct 6 2030", { start = d(2030, 10, 6), finish = d(2030, 10, 7), all_day = true } },
      {
        "tomorrow Asia/Kolkata",
        { start = d(2026, 10, 5), finish = d(2026, 10, 6), all_day = true, tz = "Asia/Kolkata" },
      },
    }
    for _, case in ipairs(cases) do
      it(("reads %q"):format(case[1]), function()
        local result, err = when.parse(case[1], ctx())
        assert.is_nil(err and err.message)
        assert.are.same(case[2], result)
      end)
    end

    it("lets parse.zones add or override an abbreviation", function()
      local result = when.parse("3pm CET", ctx({ zones = { cet = "Europe/Paris" } }))
      assert.are.equal("Europe/Paris", result.tz)
      result = when.parse("3pm ET", ctx({ zones = { et = "America/Toronto" } }))
      assert.are.equal("America/Toronto", result.tz)
    end)
  end)

  describe("errors", function()
    local cases = {
      { "", "no date or time after @", { 0, 0 } },
      { "   ", "no date or time after @", { 0, 3 } },
      { "tomorow 3pm", 'cannot read "tomorow"', { 0, 11 } },
      { "tomorrow 3pm xyz", 'unknown time zone "xyz"; add it to parse.zones', { 13, 16 } },
      { "3pm ist", 'unknown time zone "ist"; add it to parse.zones', { 4, 7 } },
      { "feb 30", "no such date", { 0, 6 } },
      { "2026-13-01", "no such date", { 0, 10 } },
      { "oct 5-3", "the range ends before it starts", { 0, 7 } },
      { "4pm-3pm", "the range ends before it starts", { 0, 7 } },
      { "3pm-3pm", "the range ends before it starts", { 0, 7 } },
      { "oct 5-7 3pm", "a date range cannot carry a time", { 8, 11 } },
      { "3pm XYZ", 'unknown time zone "XYZ"; add it to parse.zones', { 4, 7 } },
      { "tomorrow 3pm - oct 7", "a time is missing after the date", { 20, 20 } },
      { "25:00", 'cannot read "25"', { 0, 5 } },
      -- Equal is not earlier, and adding twelve to an end of 12 is not crossing noon.
      { "12-12", "the range ends before it starts", { 0, 5 } },
      { "12:30-12:15", "the range ends before it starts", { 0, 11 } },
      { "9-9", "the range ends before it starts", { 0, 3 } },
      { "0:00-0:00", "the range ends before it starts", { 0, 9 } },
      -- A flip that would need a day change is refused; write both meridiems for an overnight.
      { "3pm-3", "the range ends before it starts", { 0, 5 } },
      { "8pm-7", "the range ends before it starts", { 0, 5 } },
      { "9pm-1", "the range ends before it starts", { 0, 5 } },
      { "12pm-12", "the range ends before it starts", { 0, 7 } },
      -- A count that cannot be a plausible number of days or hours is not read (I4).
      { "in 99999 days", 'cannot read "in"', { 0, 13 } },
      { "3pm for 99999h", 'cannot read "for"', { 4, 14 } },
      { "13pm", 'cannot read "13"', { 0, 4 } },
    }
    for _, case in ipairs(cases) do
      it(("refuses %q"):format(case[1]), function()
        local result, err = when.parse(case[1], ctx())
        assert.is_nil(result)
        assert.are.same({ message = case[2], span = case[3] }, err)
      end)
    end
  end)

  it("tokenises words, numbers and punctuation with byte offsets", function()
    assert.are.same({
      { kind = "word", text = "oct", s = 0, e = 3 },
      { kind = "number", text = "2", s = 4, e = 5 },
      { kind = "punct", text = "-", s = 5, e = 6 },
      { kind = "number", text = "4", s = 6, e = 7 },
      { kind = "word", text = "New_York", s = 8, e = 16 },
    }, when.tokenize("oct 2-4 New_York"))
  end)
end)
