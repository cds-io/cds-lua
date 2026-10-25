-- Lua's value, error convention as a small Result pipeline. Only nil fails:
-- false and zero are valid successful values. A step that can refuse goes
-- through bind or traverse; one that cannot goes through map, so a reader
-- can tell the two apart at the call. Where a step cannot fail and there is
-- no error to carry, fp.map is the plain list map.
---@class cds.result
local M = {}

--- Passes the value through `fn`, which may refuse (nil, err), and an error
--- through untouched.
---@generic T, U
---@param value T?
---@param err any
---@param fn fun(value: T): U?, any
---@return U? value
---@return any err
function M.bind(value, err, fn)
  if value == nil then
    return nil, err
  end
  return fn(value)
end

--- Passes the value through `fn`, which always answers, and an error through
--- untouched. The same step as bind: the name says at the call whether `fn` can
--- refuse.
M.map = M.bind

--- Passes the value through untouched and puts `prefix` in front of an error,
--- so a failure deep in a pipeline says where it was met ('Parse error in "A
--- and": ...').
---@generic T
---@param value T?
---@param err string?
---@param prefix string
---@return T? value
---@return string? err
function M.context(value, err, prefix)
  if value == nil then
    return nil, prefix .. err
  end
  return value
end

--- Runs fn(value, index) over every item, stopping at the first refusal, and
--- answers the list of answers, or nil and that error.
---@generic T, U
---@param values T[]
---@param fn fun(value: T, index: integer): U?, any
---@return U[]? values
---@return any err
function M.traverse(values, fn)
  local out = {}
  for i, value in ipairs(values) do
    local mapped, err = fn(value, i)
    if mapped == nil then
      return nil, err
    end
    out[i] = mapped
  end
  return out
end

return require("cds.module").wrap("result", M)
