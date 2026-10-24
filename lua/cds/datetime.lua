-- Calendar arithmetic on plain wall-clock values, and the LDML format subset
-- a note needs. No clock is read here and no zone database exists: a value is
-- { year, month, day, hour?, min? } and means what it says on the wall.
--
-- Every trip through os.time goes at noon. In a zone whose clocks go forward
-- at midnight (Chile), 00:00 on the changeover day does not exist and mktime
-- moves it, so a date normalised at midnight can come back a day off; noon
-- exists on every day.
local M = {}

---@class cds.DateTime
---@field year integer
---@field month integer
---@field day integer
---@field hour integer?
---@field min integer?

---@param y integer
---@param m integer
---@return integer
function M.days_in_month(y, m)
  if m == 2 then
    local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
    return leap and 29 or 28
  end
  return ({ 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
end

---@param y any
---@param m any
---@param d any
---@return boolean
function M.is_valid(y, m, d)
  local function integer(v)
    return type(v) == "number" and v % 1 == 0
  end
  if not (integer(y) and integer(m) and integer(d)) then
    return false
  end
  -- Years os.time represents on every platform; a note needs no others.
  return y >= 1900 and y <= 9999 and m >= 1 and m <= 12 and d >= 1 and d <= M.days_in_month(y, m)
end

--- Seconds since the epoch for `dt`'s date at noon, local time.
---@param dt cds.DateTime
---@return integer
function M.to_time(dt)
  return os.time({ year = dt.year, month = dt.month, day = dt.day, hour = 12, min = 0, sec = 0 })
end

--- The date of `t` in local time; the time of day is dropped.
---@param t integer
---@return cds.DateTime
function M.from_time(t)
  local d = os.date("*t", t)
  return { year = d.year, month = d.month, day = d.day }
end

---@param dt cds.DateTime
---@param n integer
---@return cds.DateTime   -- same hour and min as `dt`
function M.add_days(dt, n)
  local out = M.from_time(M.to_time(dt) + n * 86400)
  out.hour, out.min = dt.hour, dt.min
  return out
end

--- ISO weekday: 1 is Monday, 7 is Sunday.
---@param dt cds.DateTime
---@return integer
function M.weekday(dt)
  local wday = os.date("*t", M.to_time(dt)).wday -- 1 is Sunday
  return wday == 1 and 7 or wday - 1
end

---@param first_day "monday"|"sunday"
---@return integer   -- ISO weekday number of the week's first day
local function first_weekday(first_day)
  return first_day == "sunday" and 7 or 1
end

--- The first day of the week `dt` is in.
---@param dt cds.DateTime
---@param first_day "monday"|"sunday"
---@return cds.DateTime   -- date only
function M.start_of_week(dt, first_day)
  local back = (M.weekday(dt) - first_weekday(first_day)) % 7
  return M.date_only(M.add_days(dt, -back))
end

--- The next date strictly after `dt` that falls on `wd`.
---@param dt cds.DateTime
---@param wd integer   -- ISO weekday
---@return cds.DateTime   -- date only
function M.next_weekday(dt, wd)
  local ahead = (wd - M.weekday(dt)) % 7
  return M.date_only(M.add_days(dt, ahead == 0 and 7 or ahead))
end

--- Adds minutes, crossing midnight through add_days.
---@param dt cds.DateTime
---@param minutes integer
---@return cds.DateTime
function M.add_minutes(dt, minutes)
  local total = (dt.hour or 0) * 60 + (dt.min or 0) + minutes
  local days = math.floor(total / 1440)
  local rem = total - days * 1440
  local out = M.add_days(dt, days)
  out.hour, out.min = math.floor(rem / 60), rem % 60
  return out
end

---@param dt cds.DateTime
---@return cds.DateTime
function M.date_only(dt)
  return { year = dt.year, month = dt.month, day = dt.day }
end

---@param dt cds.DateTime
---@param hour integer
---@param min integer
---@return cds.DateTime
function M.with_time(dt, hour, min)
  return { year = dt.year, month = dt.month, day = dt.day, hour = hour, min = min }
end

--- Orders two values; a missing time counts as midnight.
---@param a cds.DateTime
---@param b cds.DateTime
---@return integer   -- -1, 0 or 1
function M.compare(a, b)
  for _, f in ipairs({ "year", "month", "day", "hour", "min" }) do
    local x, y = a[f] or 0, b[f] or 0
    if x ~= y then
      return x < y and -1 or 1
    end
  end
  return 0
end

-- LDML -------------------------------------------------------------------------
-- The tokens a note's date format needs. A format is a string of these plus
-- literal characters: "yyyy-MM-dd", "M/d", "d.M.yyyy", "h:mm a".

local TOKENS = {
  yyyy = { pattern = "(%d%d%d%d)", field = "year" },
  yy = { pattern = "(%d%d)", field = "year", short = true },
  MM = { pattern = "(%d%d)", field = "month" },
  M = { pattern = "(%d%d?)", field = "month" },
  dd = { pattern = "(%d%d)", field = "day" },
  d = { pattern = "(%d%d?)", field = "day" },
  HH = { pattern = "(%d%d)", field = "hour" },
  H = { pattern = "(%d%d?)", field = "hour" },
  hh = { pattern = "(%d%d)", field = "hour", twelve = true },
  h = { pattern = "(%d%d?)", field = "hour", twelve = true },
  mm = { pattern = "(%d%d)", field = "min" },
  a = { pattern = "([AaPp][Mm])", field = "meridiem" },
}

---@class cds.datetime.Format
---@field parts table[]      -- { token = <name> } or { literal = <text> }
---@field pattern string     -- a Lua pattern matching the whole text

--- Checks a format once. An unknown token is the error, so a typo in
--- configuration fails at setup, never at parse time.
---@param format string
---@return cds.datetime.Format? compiled
---@return string? err
function M.compile(format)
  local parts, pattern, i = {}, "^", 1
  while i <= #format do
    local c = format:sub(i, i)
    if c:match("%a") then
      local run = format:match("^" .. c .. "+", i)
      if not TOKENS[run] then
        return nil, ("unknown token %q in format %q"):format(run, format)
      end
      parts[#parts + 1] = { token = run }
      pattern = pattern .. TOKENS[run].pattern
      i = i + #run
    else
      parts[#parts + 1] = { literal = c }
      pattern = pattern .. (c:match("%w") and c or "%" .. c)
      i = i + 1
    end
  end
  return { parts = parts, pattern = pattern .. "$" }
end

---@param dt cds.DateTime
---@param format string|cds.datetime.Format
---@return string
function M.format(dt, format)
  local compiled = type(format) == "string" and assert(M.compile(format)) or format
  local out = {}
  for _, part in ipairs(compiled.parts) do
    if part.literal then
      out[#out + 1] = part.literal
    else
      local spec = TOKENS[part.token]
      local v = dt[spec.field]
      if spec.field == "meridiem" then
        out[#out + 1] = (dt.hour or 0) < 12 and "AM" or "PM"
      elseif spec.twelve then
        v = (v or 0) % 12
        out[#out + 1] = (#part.token == 2 and "%02d" or "%d"):format(v == 0 and 12 or v)
      elseif spec.short then
        out[#out + 1] = ("%02d"):format((v or 0) % 100)
      else
        out[#out + 1] = (#part.token >= 2 and "%02d" or "%d"):format(v or 0)
      end
    end
  end
  return table.concat(out)
end

--- Reads `text` as `format`, whole. The result holds only the fields the
--- format names; a date's validity is the caller's check (is_valid).
---@param text string
---@param format string|cds.datetime.Format
---@return cds.DateTime? dt
function M.parse(text, format)
  local compiled = type(format) == "string" and assert(M.compile(format)) or format
  local captures = { text:match(compiled.pattern) }
  if #captures == 0 then
    return nil
  end
  local dt, n, meridiem = {}, 0, nil
  for _, part in ipairs(compiled.parts) do
    if part.token then
      n = n + 1
      local spec = TOKENS[part.token]
      if spec.field == "meridiem" then
        meridiem = captures[n]:lower()
      else
        local v = tonumber(captures[n])
        if spec.short then
          v = v + (v < 70 and 2000 or 1900)
        end
        dt[spec.field] = v
      end
    end
  end
  if meridiem and dt.hour then
    if dt.hour < 1 or dt.hour > 12 then
      return nil
    end
    dt.hour = dt.hour % 12 + (meridiem == "pm" and 12 or 0)
  end
  return dt
end

return require("cds.module")("datetime", M)
