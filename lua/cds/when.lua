-- Reads a date-and-time phrase: "tomorrow 3pm", "next monday 9-9:30 ET",
-- "oct 2-4", "2026-10-02 14:00 for 45m". The text is tokenised, then an
-- ordered set of rules consumes tokens from the front, each contributing a
-- date, a time, a range end, a duration or a zone; what is left over is the
-- error, with its span. English only; the words are the table below.
--
-- The phrase is expected to stand alone (calplus bounds it with "@"), so the
-- reading is strict: a token no rule takes is an error, never skipped.
local datetime = require("cds.datetime")

---@class cds.when
local M = {}

-- Words -----------------------------------------------------------------------

M.words = {
  relative = { today = 0, tomorrow = 1, yesterday = -1 },
  weekdays = {
    monday = 1,
    mon = 1,
    tuesday = 2,
    tue = 2,
    tues = 2,
    wednesday = 3,
    wed = 3,
    thursday = 4,
    thu = 4,
    thur = 4,
    thurs = 4,
    friday = 5,
    fri = 5,
    saturday = 6,
    sat = 6,
    sunday = 7,
    sun = 7,
  },
  months = {
    january = 1,
    jan = 1,
    february = 2,
    feb = 2,
    march = 3,
    mar = 3,
    april = 4,
    apr = 4,
    may = 5,
    june = 6,
    jun = 6,
    july = 7,
    jul = 7,
    august = 8,
    aug = 8,
    september = 9,
    sep = 9,
    sept = 9,
    october = 10,
    oct = 10,
    november = 11,
    nov = 11,
    december = 12,
    dec = 12,
  },
  ordinals = { st = true, nd = true, rd = true, th = true },
  meridiem = { am = "am", pm = "pm", a = "am", p = "pm" },
  named_times = { noon = { 12, 0 }, midnight = { 0, 0 } },
  units = { day = 1, days = 1, week = 7, weeks = 7 },
  duration_units = {
    m = 1,
    min = 1,
    mins = 1,
    minute = 1,
    minutes = 1,
    h = 60,
    hr = 60,
    hrs = 60,
    hour = 60,
    hours = 60,
  },
  range = { to = true },
  ["for"] = "for",
  ["in"] = "in",
  this = "this",
  next = "next",
  last = "last",
}

-- The zones a note may abbreviate. Abbreviations are ambiguous worldwide, so
-- this stays small and a caller merges its own over it (ctx.zones).
M.zones = {
  utc = "UTC",
  gmt = "UTC",
  z = "UTC",
  et = "America/New_York",
  est = "America/New_York",
  edt = "America/New_York",
  ct = "America/Chicago",
  cst = "America/Chicago",
  cdt = "America/Chicago",
  mt = "America/Denver",
  mst = "America/Denver",
  mdt = "America/Denver",
  pt = "America/Los_Angeles",
  pst = "America/Los_Angeles",
  pdt = "America/Los_Angeles",
  akt = "America/Anchorage",
  akst = "America/Anchorage",
  akdt = "America/Anchorage",
  hst = "Pacific/Honolulu",
}

-- Tokens ----------------------------------------------------------------------

---@class cds.when.Token
---@field kind "word"|"number"|"punct"
---@field text string      -- as written; words are compared lower-cased
---@field s integer        -- 0-based byte offset, inclusive
---@field e integer        -- 0-based byte offset, exclusive

local EN_DASH = "\226\128\147"

---@param text string
---@return cds.when.Token[]
function M.tokenize(text)
  local tokens, i = {}, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c:match("%d") then
      local run = text:match("^%d+", i)
      tokens[#tokens + 1] = { kind = "number", text = run, s = i - 1, e = i - 1 + #run }
      i = i + #run
    elseif c:match("[%a_]") then
      local run = text:match("^[%a_]+", i)
      tokens[#tokens + 1] = { kind = "word", text = run, s = i - 1, e = i - 1 + #run }
      i = i + #run
    elseif text:sub(i, i + 2) == EN_DASH then
      tokens[#tokens + 1] = { kind = "punct", text = "-", s = i - 1, e = i + 2 }
      i = i + 3
    else
      -- One byte of anything else; a multibyte character becomes one token
      -- per byte, which only matters for the span of an error.
      tokens[#tokens + 1] = { kind = "punct", text = c, s = i - 1, e = i }
      i = i + 1
    end
  end
  return tokens
end

-- A cursor over the tokens ------------------------------------------------------

local Cursor = {}
Cursor.__index = Cursor

local function cursor(tokens)
  return setmetatable({ tokens = tokens, i = 1 }, Cursor)
end

function Cursor:peek(n)
  return self.tokens[self.i + (n or 0)]
end

function Cursor:done()
  return self.i > #self.tokens
end

function Cursor:word(n)
  local t = self:peek(n)
  return t and t.kind == "word" and t.text:lower() or nil
end

function Cursor:number(n)
  local t = self:peek(n)
  return t and t.kind == "number" and t.text or nil
end

function Cursor:punct(n, ch)
  local t = self:peek(n)
  return t and t.kind == "punct" and t.text == ch
end

function Cursor:take(n)
  local first = self.tokens[self.i]
  self.i = self.i + n
  return first
end

--- Is the next token a range separator ("-" or "to")?
function Cursor:separator()
  return self:punct(0, "-") or self:word(0) == "to"
end

---@param a cds.when.Token
---@param b cds.when.Token?
---@return integer[]
local function span(a, b)
  return { a.s, (b or a).e }
end

-- Dates -----------------------------------------------------------------------

---@class cds.when.Ctx
---@field now cds.DateTime
---@field first_day_of_week "monday"|"sunday"
---@field default_duration integer
---@field formats string[]|table[]   -- LDML formats for numeric dates
---@field zones table<string, string>?

local function today(ctx)
  return datetime.date_only(ctx.now)
end

--- A date with no year: the next year in which it exists and is not before
--- today (feb 29 said in 2026 is 2028's).
local function next_occurrence(ctx, month, day)
  local y = ctx.now.year
  for _ = 0, 8 do
    local candidate = { year = y, month = month, day = day }
    if datetime.is_valid(y, month, day) and datetime.compare(candidate, today(ctx)) >= 0 then
      return candidate
    end
    y = y + 1
  end
  return { year = ctx.now.year, month = month, day = day } -- invalid on purpose: is_valid reports it
end

--- Reads a day number with an optional ordinal suffix ("2", "2nd").
---@return integer? day, integer tokens
local function day_number(cur, n)
  local num = cur:number(n)
  if not num or #num > 2 then
    return nil, 0
  end
  local suffix = cur:word(n + 1)
  if suffix and M.words.ordinals[suffix] and cur:peek(n + 1).s == cur:peek(n).e then
    return tonumber(num), 2
  end
  return tonumber(num), 1
end

-- A four-digit number after a date is a year only when it can be one; "oct 6
-- 0930" carries a compact time. 2030 is a year (the design's reading); write
-- 20:30 for the time.
local function optional_year(cur, n)
  local num = cur:number(n)
  if num and #num == 4 and tonumber(num) >= 1900 then
    return tonumber(num), 1
  end
  return nil, 0
end

--- A weekday, with this/next/last in front. Consumes 1 or 2 tokens.
local function weekday_date(cur, ctx)
  local first = cur:word(0)
  local qualifier, wd, count
  if first == "this" or first == "next" or first == "last" then
    qualifier, wd, count = first, M.words.weekdays[cur:word(1) or ""], 2
  else
    wd, count = M.words.weekdays[first or ""], 1
  end
  if not wd then
    return nil
  end
  local from = today(ctx)
  local date
  if not qualifier then
    date = datetime.next_weekday(from, wd)
  else
    local first_day = ctx.first_day_of_week == "sunday" and 7 or 1
    local week = datetime.start_of_week(from, ctx.first_day_of_week)
    local offset = ({ this = 0, next = 7, last = -7 })[qualifier]
    date = datetime.add_days(week, offset + (wd - first_day) % 7)
  end
  return { date = date, span = span(cur:peek(0), cur:peek(count - 1)) }, count
end

--- "oct 2", "2 oct", "october 2nd, 2027", "oct 2 2027"
local function month_name_date(cur, ctx)
  local month = M.words.months[cur:word(0) or ""]
  local day, day_tokens, count
  if month then
    day, day_tokens = day_number(cur, 1)
    if not day then
      return nil
    end
    count = 1 + day_tokens
  else
    day, day_tokens = day_number(cur, 0)
    month = day and M.words.months[cur:word(day_tokens) or ""]
    if not month then
      return nil
    end
    count = day_tokens + 1
  end
  if cur:punct(count, ",") then
    count = count + 1
  end
  local year, year_tokens = optional_year(cur, count)
  count = count + year_tokens
  local date = year and { year = year, month = month, day = day } or next_occurrence(ctx, month, day)
  return { date = date, span = span(cur:peek(0), cur:peek(count - 1)), month = month }, count
end

--- yyyy-mm-dd
local function iso_date(cur)
  local y, m, d = cur:number(0), cur:number(2), cur:number(4)
  if y and #y == 4 and cur:punct(1, "-") and m and cur:punct(3, "-") and d then
    return {
      date = { year = tonumber(y), month = tonumber(m), day = tonumber(d) },
      span = span(cur:peek(0), cur:peek(4)),
    },
      5
  end
  return nil
end

--- A date in one of ctx.formats, read from the raw text up to the next space.
local function formatted_date(cur, ctx, text)
  local first = cur:peek(0)
  if not first or not ctx.formats or #ctx.formats == 0 then
    return nil
  end
  local chunk = text:sub(first.s + 1):match("^%S+")
  for _, format in ipairs(ctx.formats) do
    local parsed = datetime.parse(chunk, format)
    if parsed and parsed.month and parsed.day then
      local e = first.s + #chunk
      local count = 0
      while cur:peek(count) and cur:peek(count).e <= e do
        count = count + 1
      end
      local date = { year = parsed.year or ctx.now.year, month = parsed.month, day = parsed.day }
      if not parsed.year then
        date = next_occurrence(ctx, parsed.month, parsed.day)
      end
      return { date = date, span = { first.s, e } }, count
    end
  end
  return nil
end

--- "today", "tomorrow", "in 3 days", "in 2 weeks"
local function relative_date(cur, ctx)
  local w = cur:word(0)
  if w and M.words.relative[w] then
    return { date = datetime.add_days(today(ctx), M.words.relative[w]), span = span(cur:peek(0)) }, 1
  end
  if w == "in" and cur:number(1) and #cur:number(1) <= 4 and M.words.units[cur:word(2) or ""] then
    local days = tonumber(cur:number(1)) * M.words.units[cur:word(2)]
    return { date = datetime.add_days(today(ctx), days), span = span(cur:peek(0), cur:peek(2)) }, 3
  end
  return nil
end

--- Any date form. Returns { date, span, month? } and the tokens consumed.
local function parse_date(cur, ctx, text)
  for _, rule in ipairs({ relative_date, weekday_date, iso_date, month_name_date }) do
    local found, count = rule(cur, ctx)
    if found then
      return found, count
    end
  end
  return formatted_date(cur, ctx, text)
end

-- Times -------------------------------------------------------------------------

--- A time: "3pm", "9 AM", "9", "9:30", "0930", "315a", "14:00", "noon".
--- Returns { hour, min, meridiem?, span } and the tokens consumed.
local function parse_time(cur)
  local w = cur:word(0)
  if w and M.words.named_times[w] then
    local hm = M.words.named_times[w]
    return { hour = hm[1], min = hm[2], meridiem = "24h", span = span(cur:peek(0)) }, 1
  end
  local num = cur:number(0)
  if not num then
    return nil
  end
  local hour, min, count
  if cur:punct(1, ":") and cur:number(2) and #cur:number(2) == 2 then
    hour, min, count = tonumber(num), tonumber(cur:number(2)), 3
    if #num > 2 then
      return nil
    end
  elseif #num <= 2 then
    hour, min, count = tonumber(num), 0, 1
  elseif #num <= 4 then
    -- Compact: 315 is 3:15, 0930 is 09:30, 1730 is 17:30.
    hour, min, count = tonumber(num:sub(1, -3)), tonumber(num:sub(-2)), 1
  else
    return nil
  end
  local meridiem
  local suffix = cur:word(count)
  if suffix and M.words.meridiem[suffix] then
    -- "a" and "p" only when glued to the number ("315a"); "am"/"pm" either way.
    if #suffix == 2 or cur:peek(count).s == cur:peek(count - 1).e then
      meridiem = M.words.meridiem[suffix]
      count = count + 1
    end
  end
  if min > 59 or hour > 23 or (meridiem and (hour < 1 or hour > 12)) then
    return nil
  end
  return { hour = hour, min = min, meridiem = meridiem, span = span(cur:peek(0), cur:peek(count - 1)) }, count
end

--- Applies a meridiem: 12am is 00:00, 12pm is 12:00.
local function to_24h(t, meridiem)
  if meridiem == "am" then
    return t.hour % 12
  elseif meridiem == "pm" then
    return t.hour % 12 + 12
  end
  return t.hour
end

---@param t table
---@return integer
local function minute_of_day(t, hour)
  return hour * 60 + t.min
end

--- Resolves a start and an end time into hours and minutes. The rules:
---
--- - both explicit (`3pm-4pm`, `10pm-2am`): as written; the caller decides
---   whether an end before the start crosses midnight
--- - one explicit (`3-4pm`, `9am-1`): the bare side inherits the meridiem;
---   if that puts the end at or before the start, the other half of the day
---   is tried; if that does not land the end after the start on the same day
---   either, the pair is returned as inherited and the caller refuses it
---   (`3pm-3`, `8pm-7`: write both meridiems for an overnight)
--- - neither (`11-1`, `noon-1`; a named time counts as bare): as written,
---   except that an end earlier than a start of 12 or below crosses noon
---   (`11-1` is 11:00 to 13:00; `12-12` is refused, since equal is not earlier)
---@return integer, integer, integer, integer   -- start h, m, end h, m
local function resolve_range(a, b)
  local am = a.meridiem ~= "24h" and a.meridiem or nil
  local bm = b.meridiem ~= "24h" and b.meridiem or nil
  if am and bm then
    return to_24h(a, am), a.min, to_24h(b, bm), b.min
  end
  local function other(m)
    return m == "am" and "pm" or "am"
  end
  if am and b.meridiem == nil then
    local sh = to_24h(a, am)
    for _, m in ipairs({ am, other(am) }) do
      if b.hour >= 1 and b.hour <= 12 and minute_of_day(b, to_24h(b, m)) > minute_of_day(a, sh) then
        return sh, a.min, to_24h(b, m), b.min
      end
    end
    return sh, a.min, to_24h(b, am), b.min
  elseif bm and a.meridiem == nil then
    local eh = to_24h(b, bm)
    for _, m in ipairs({ bm, other(bm) }) do
      if a.hour >= 1 and a.hour <= 12 and minute_of_day(a, to_24h(a, m)) < minute_of_day(b, eh) then
        return to_24h(a, m), a.min, eh, b.min
      end
    end
    return to_24h(a, bm), a.min, eh, b.min
  end
  local sh, eh = to_24h(a, a.meridiem), to_24h(b, b.meridiem)
  local crosses_noon = minute_of_day(b, eh) < minute_of_day(a, sh) and eh < 12 and sh <= 12 and b.meridiem ~= "24h"
  if crosses_noon then
    eh = eh + 12
  end
  return sh, a.min, eh, b.min
end

--- "for 45m", "for 1h", "for 1h30", "for 2 hours"
---@return integer? minutes, integer tokens
local function parse_duration(cur)
  if cur:word(0) ~= "for" or not cur:number(1) or #cur:number(1) > 4 then
    return nil, 0
  end
  local unit = M.words.duration_units[cur:word(2) or ""]
  if not unit then
    return nil, 0
  end
  local minutes, count = tonumber(cur:number(1)) * unit, 3
  if unit == 60 and cur:number(3) and cur:peek(3).s == cur:peek(2).e then
    minutes, count = minutes + tonumber(cur:number(3)), 4
    if M.words.duration_units[cur:word(4) or ""] == 1 and cur:peek(4).s == cur:peek(3).e then
      count = 5
    end
  end
  return minutes, count
end

-- Zones -------------------------------------------------------------------------

--- "ET", "UTC", "Europe/Paris". Returns the IANA name and the tokens consumed,
--- or false with a message when the word looks like a zone but is unknown.
local function parse_zone(cur, ctx, text)
  local first = cur:peek(0)
  if not first or first.kind ~= "word" then
    return nil, 0
  end
  local raw = text:sub(first.s + 1):match("^%S+")
  if raw:find("/", 1, true) and raw:match("^%a[%w_+%-]*/[%w_+%-/]+$") then
    local e, count = first.s + #raw, 0
    while cur:peek(count) and cur:peek(count).e <= e do
      count = count + 1
    end
    return raw, count
  end
  local key = first.text:lower()
  local zone = (ctx.zones and ctx.zones[key]) or (ctx.zones and ctx.zones[first.text]) or M.zones[key]
  if zone then
    return zone, 1
  end
  -- By this point nothing else can be meant by a short last word.
  if #first.text <= 5 and not cur:peek(1) then
    return false, 0, ("unknown time zone %q; add it to parse.zones"):format(first.text)
  end
  return nil, 0
end

-- The phrase --------------------------------------------------------------------

---@class cds.when.Result
---@field start cds.DateTime
---@field finish cds.DateTime
---@field all_day boolean
---@field tz string?

---@class cds.when.Error
---@field message string
---@field span integer[]   -- 0-based byte offsets into the text, end-exclusive

local function fail(message, s, e)
  return nil, { message = message, span = { s, e } }
end

---@param text string
---@param ctx cds.when.Ctx
---@return cds.when.Result? result
---@return cds.when.Error? err
function M.parse(text, ctx)
  local tokens = M.tokenize(text)
  if #tokens == 0 then
    return fail("no date or time after @", 0, #text)
  end
  local cur = cursor(tokens)

  -- [date [- date]]
  local first_date, count = parse_date(cur, ctx, text)
  local last_date
  if first_date then
    cur:take(count)
    if not datetime.is_valid(first_date.date.year, first_date.date.month, first_date.date.day) then
      return fail("no such date", first_date.span[1], first_date.span[2])
    end
    if cur:separator() then
      local save = cur.i
      cur:take(1)
      -- "oct 2-4": a bare day number continues the month.
      local second, n2
      if first_date.month and cur:number(0) then
        local day, day_tokens = day_number(cur, 0)
        local after = cur:word(day_tokens)
        local is_time = cur:punct(day_tokens, ":") or (after and M.words.meridiem[after])
        if day and not is_time and not (after and M.words.months[after]) then
          second = {
            date = { year = first_date.date.year, month = first_date.month, day = day },
            span = span(cur:peek(0), cur:peek(day_tokens - 1)),
          }
          n2 = day_tokens
        end
      end
      if not second then
        second, n2 = parse_date(cur, ctx, text)
      end
      if second then
        cur:take(n2)
        if not datetime.is_valid(second.date.year, second.date.month, second.date.day) then
          return fail("no such date", second.span[1], second.span[2])
        end
        last_date = second
      else
        cur.i = save
      end
    end
  end

  -- [time [- [date] time | for duration]]
  local start_time, end_time, end_date, duration
  local t1, n1 = parse_time(cur)
  if t1 then
    cur:take(n1)
    start_time = t1
    if cur:separator() then
      local save = cur.i
      cur:take(1)
      local d2, dn = parse_date(cur, ctx, text)
      if d2 then
        cur:take(dn)
        if not datetime.is_valid(d2.date.year, d2.date.month, d2.date.day) then
          return fail("no such date", d2.span[1], d2.span[2])
        end
      end
      local t2, tn = parse_time(cur)
      if t2 then
        cur:take(tn)
        end_time, end_date = t2, d2
      elseif d2 then
        return fail("a time is missing after the date", d2.span[2], d2.span[2])
      else
        cur.i = save
      end
    else
      local minutes, dn = parse_duration(cur)
      if minutes then
        cur:take(dn)
        duration = minutes
      end
    end
  end

  -- [zone]
  local tz
  local zone, zn, zone_err = parse_zone(cur, ctx, text)
  if zone then
    cur:take(zn)
    tz = zone
  elseif zone == false then
    local t = cur:peek(0)
    return fail(zone_err, t.s, t.e)
  end

  if not cur:done() then
    local t = cur:peek(0)
    return fail(("cannot read %q"):format(text:sub(t.s + 1, t.e)), t.s, tokens[#tokens].e)
  end
  if not first_date and not start_time then
    return fail("no date or time after @", 0, #text)
  end

  -- Resolve.
  local date = first_date and first_date.date or today(ctx)
  if not start_time then
    local last = last_date and last_date.date or date
    if datetime.compare(last, date) < 0 then
      return fail("the range ends before it starts", 0, tokens[#tokens].e)
    end
    return {
      start = datetime.date_only(date),
      finish = datetime.add_days(datetime.date_only(last), 1),
      all_day = true,
      tz = tz,
    }
  end
  if last_date then
    return fail("a date range cannot carry a time", start_time.span[1], start_time.span[2])
  end
  local sh, sm, eh, em
  if end_time then
    sh, sm, eh, em = resolve_range(start_time, end_time)
  else
    sh, sm = to_24h(start_time, start_time.meridiem), start_time.min
  end
  local start = datetime.with_time(date, sh, sm)
  local finish
  if end_time then
    finish = datetime.with_time(end_date and end_date.date or date, eh, em)
    -- "10pm - 2am": an evening start with a morning end runs into the next day.
    if not end_date and sh >= 12 and eh < 12 then
      finish = datetime.add_days(finish, 1)
    end
  else
    finish = datetime.add_minutes(start, duration or ctx.default_duration)
  end
  if datetime.compare(finish, start) <= 0 then
    return fail("the range ends before it starts", 0, tokens[#tokens].e)
  end
  return { start = start, finish = finish, all_day = false, tz = tz }
end

return require("cds.module").wrap("when", M)
