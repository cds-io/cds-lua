-- Builds the positional arguments of a command line from declared values, so
-- that the dynamic values reaching a CLI are checked in one place. The fixed
-- part (the program and its own options) is the caller's and is trusted, and
-- `command` places whatever strings it is given: the check holds for a caller
-- that hands it only what `render` returned. The shape follows Rust's bpaf:
-- a value is a name plus a chain of `parse`, `map` and `guard` steps, each
-- guard carries its own message, values compose into an ordered list, and the
-- list is only ever placed after "--" (bpaf's strict positionals), so nothing
-- in it can be read as an option.
--
-- bpaf parses a command line into values; this renders values into one. The
-- direction is reversed and the structure is the same.
local M = {}

---@class cds.argv.Value
---@field name string
---@field private steps table[]
local Value = {}
Value.__index = Value

--- A named value with no steps yet. Steps return a new value, so a value can
--- be shared and extended without affecting its other users.
---@param name string   -- used in messages: "invalid <name>: <input>"
---@return cds.argv.Value
function M.value(name)
  return setmetatable({ name = name, steps = {} }, Value)
end

---@private
function Value:with(step)
  local steps = vim.list_extend({}, self.steps)
  table.insert(steps, step)
  return setmetatable({ name = self.name, steps = steps }, Value)
end

--- Transform the value.
---@param fn fun(v: any): any
---@return cds.argv.Value
function Value:map(fn)
  return self:with({ map = fn })
end

--- Require a condition. `message` is the whole error, or a function of the value.
---@param pred fun(v: any): boolean
---@param message string|fun(v: any): string
---@return cds.argv.Value
function Value:guard(pred, message)
  return self:with({ guard = pred, message = message })
end

--- Convert the value, or refuse it: `fn` returns the new value, or nil to
--- fail with "invalid <name>: <input>".
---@param fn fun(v: any): any?
---@return cds.argv.Value
function Value:parse(fn)
  return self:with({ parse = fn })
end

--- Run the steps on `input`. The result is always text without a NUL byte,
--- whatever the steps allowed: argv entries are C strings, so an embedded NUL
--- cannot be part of one. (Passed anyway, the value arrives cut short at the
--- NUL with no error: "nul\0byte" reached osascript as "nul".)
---@param input any
---@return string? text
---@return string? err
function Value:render(input)
  local v = input
  for _, step in ipairs(self.steps) do
    if step.map then
      v = step.map(v)
    elseif step.guard then
      if not step.guard(v) then
        return nil, type(step.message) == "function" and step.message(v) or step.message
      end
    else
      local parsed = step.parse(v)
      if parsed == nil then
        return nil, ("invalid %s: %s"):format(self.name, tostring(v))
      end
      v = parsed
    end
  end
  if type(v) ~= "string" then
    return nil, ("%s did not render as text"):format(self.name)
  elseif v:find("%z") then
    return nil, ("%s contains a NUL byte"):format(self.name)
  end
  return v
end

-- Guards ---------------------------------------------------------------------

---@param v any
---@return boolean
function M.is_text(v)
  return type(v) == "string"
end

---@param v any
---@return boolean
function M.not_blank(v)
  return type(v) == "string" and v:find("%S") ~= nil
end

-- C0 controls (NUL, tab and newline among them) and DEL.
local CONTROL = "[%z\1-\31\127]"

--- No control characters.
---@param v any
---@return boolean
function M.printable(v)
  return type(v) == "string" and not v:find(CONTROL)
end

-- Control characters other than a newline or a tab: what text that may
-- span lines must not carry.
local CONTROL_EXCEPT_LINES = "[%z\1-\8\11\12\14-\31\127]"

--- No control characters except newlines and tabs.
---@param v any
---@return boolean
function M.printable_lines(v)
  return type(v) == "string" and not v:find(CONTROL_EXCEPT_LINES)
end

---@param n integer
---@return fun(v: any): boolean
function M.max_bytes(n)
  return function(v)
    return type(v) == "string" and #v <= n
  end
end

-- Maps -------------------------------------------------------------------------

--- Each control character becomes one space.
---@param v string
---@return string
function M.spaces_for_control(v)
  return (v:gsub(CONTROL, " "))
end

--- The same, keeping newlines and tabs.
---@param v string
---@return string
function M.spaces_for_control_except_lines(v)
  return (v:gsub(CONTROL_EXCEPT_LINES, " "))
end

-- Parsers ----------------------------------------------------------------------

--- A whole number within [lo, hi], rendered in decimal.
---@param lo integer
---@param hi integer
---@return fun(v: any): string?
function M.integer(lo, hi)
  return function(v)
    if type(v) == "number" and v % 1 == 0 and v >= lo and v <= hi then
      return ("%d"):format(v)
    end
    return nil
  end
end

--- true or false, and nothing else.
---@param v any
---@return string?
function M.boolean(v)
  if type(v) == "boolean" then
    return tostring(v)
  end
  return nil
end

-- Composition ------------------------------------------------------------------

---@class cds.argv.Positional
---@field private values cds.argv.Value[]
local Positional = {}
Positional.__index = Positional

--- An ordered list of values, rendered all or nothing.
---@param values cds.argv.Value[]
---@return cds.argv.Positional
function M.positional(values)
  return setmetatable({ values = vim.list_extend({}, values) }, Positional)
end

--- One input per value, in order. An input may be nil (its value's steps
--- decide what that means); set `inputs.n` when the last one might be, since
--- a Lua list cannot show a trailing nil.
---@param inputs any[]
---@return string[]? args
---@return string? err   -- the first value that failed
function Positional:render(inputs)
  local given = inputs.n or table.maxn(inputs)
  if given ~= #self.values then
    return nil, ("expected %d values, got %d"):format(#self.values, given)
  end
  local args = {}
  for i, value in ipairs(self.values) do
    local text, err = value:render(inputs[i])
    if not text then
      return nil, err
    end
    args[i] = text
  end
  return args
end

--- The full argv: `fixed`, then "--", then `values`. The separator ends the
--- program's option parsing, so a value that begins with a dash stays a value.
--- Neither list is inspected: `values` should be what a `render` returned.
---@param fixed string[]    -- the program and its own options
---@param values string[]   -- rendered values
---@return string[]
function M.command(fixed, values)
  local argv = vim.list_extend({}, fixed)
  table.insert(argv, "--")
  return vim.list_extend(argv, values)
end

return M
