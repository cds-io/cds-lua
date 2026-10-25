---@tag cds.fp
---@toc_entry Lists
---@text
--- map, filter, reduce, find, find_map, any, all, set and unique over
--- lists: the house list vocabulary, for the pure modules in the first place,
--- which run under plain Lua 5.1 (none of these built in) and without `vim`,
--- so without vim.iter. A list is a sequence (items at 1..n, no holes), read
--- with ipairs. Map, filter and unique return fresh lists, set a fresh table,
--- reduce the final accumulator, find the item, any and all a boolean. The
--- helpers do not modify the input list. The function argument comes last, so
--- one written out over several lines reads as a block.
---@class cds.fp
local M = {}

--- Builds the list of fn(item, index) for each item, in order. A nil result is
--- an error: it would leave a hole, and ipairs would stop reading the list
--- there.
---@generic T, U
---@param list T[]
---@param fn fun(item: T, index: integer): U
---@return U[]
function M.map(list, fn)
  local out = {}
  for index, item in ipairs(list) do
    local mapped = fn(item, index)
    if mapped == nil then
      error("fp.map: the function returned nil for item " .. index, 2)
    end
    out[index] = mapped
  end
  return out
end

--- Keeps the items for which keep(item, index) is true, in order.
---@generic T
---@param list T[]
---@param keep fun(item: T, index: integer): any
---@return T[]
function M.filter(list, keep)
  local out = {}
  for index, item in ipairs(list) do
    if keep(item, index) then
      out[#out + 1] = item
    end
  end
  return out
end

--- Folds the items into one value, left to right: the result of fn(value, item,
--- index) is the value the next item meets, starting from `initial`, which is
--- also what an empty list gives.
---@generic T, A
---@param list T[]
---@param initial A
---@param fn fun(value: A, item: T, index: integer): A
---@return A
function M.reduce(list, initial, fn)
  local value = initial
  for index, item in ipairs(list) do
    value = fn(value, item, index)
  end
  return value
end

--- Finds the first item for which test(item, index) is truthy and answers it
--- with its index; nil when none is. The lists here hold nodes, strings and
--- records, never false, so a falsy answer means no item.
---@generic T
---@param list T[]
---@param test fun(item: T, index: integer): any
---@return T? item
---@return integer? index
function M.find(list, test)
  for index, item in ipairs(list) do
    if test(item, index) then
      return item, index
    end
  end
end

--- Answers the first non-nil fn(item, index), stopping there; nil when every
--- item answers nil. One pass that finds and transforms at once, for a chain of
--- parsers tried in order: the first that reads the line gives the record.
---@generic T, U
---@param list T[]
---@param fn fun(item: T, index: integer): U?
---@return U?
function M.find_map(list, fn)
  for index, item in ipairs(list) do
    local found = fn(item, index)
    if found ~= nil then
      return found
    end
  end
end

--- Joins the lists fn(item, index) answers, in order: a map whose answers are
--- lists, flattened one level.
---@generic T, U
---@param list T[]
---@param fn fun(item: T, index: integer): U[]
---@return U[]
function M.flat_map(list, fn)
  local out = {}
  for index, item in ipairs(list) do
    for _, found in ipairs(fn(item, index)) do
      out[#out + 1] = found
    end
  end
  return out
end

--- Lists the keys of a table, in no particular order; sort it when the order
--- matters.
---@generic K
---@param t table<K, any>
---@return K[]
function M.keys(t)
  local out = {}
  for key in pairs(t) do
    out[#out + 1] = key
  end
  return out
end

--- Calls fn(item, index) for each item, in order, for what it does; the answers
--- are dropped. Where map builds a list, each performs an action per item: a
--- cursor set in every window showing a buffer.
---@generic T
---@param list T[]
---@param fn fun(item: T, index: integer)
function M.each(list, fn)
  for index, item in ipairs(list) do
    fn(item, index)
  end
end

--- Keeps every non-nil fn(item, index), in order. One pass that filters and
--- transforms at once, for a reading that keeps what it can parse: the heading
--- each line carries, for the lines that carry one.
---@generic T, U
---@param list T[]
---@param fn fun(item: T, index: integer): U?
---@return U[]
function M.filter_map(list, fn)
  local out = {}
  for index, item in ipairs(list) do
    local found = fn(item, index)
    if found ~= nil then
      out[#out + 1] = found
    end
  end
  return out
end

--- Does test(item, index) hold for some item? Stops at the first.
---@generic T
---@param list T[]
---@param test fun(item: T, index: integer): any
---@return boolean
function M.any(list, test)
  for index, item in ipairs(list) do
    if test(item, index) then
      return true
    end
  end
  return false
end

--- Does test(item, index) hold for every item? Stops at the first that
--- fails; true for an empty list.
---@generic T
---@param list T[]
---@param test fun(item: T, index: integer): any
---@return boolean
function M.all(list, test)
  for index, item in ipairs(list) do
    if not test(item, index) then
      return false
    end
  end
  return true
end

--- Finds the key an item is filed under: key(item, index), or the item itself
--- without a key function. A nil key is an error, naming the item, since Lua
--- would refuse the nil index without saying which item gave it.
---@param name string                               -- the caller, for the message
---@param key? fun(item: any, index: integer): any
---@param item any
---@param index integer
---@return any
local function key_of(name, key, item, index)
  -- Spelled out: `key and key(item, index) or item` would fall back to
  -- the item on a nil key, which is the case to refuse.
  local found = item
  if key then
    found = key(item, index)
  end
  if found == nil then
    error("fp." .. name .. ": the key function returned nil for item " .. index, 3)
  end
  return found
end

--- Builds a set of the items: a table of each one's key to true.
---@generic T
---@param list T[]
---@param key? fun(item: T, index: integer): any   -- the item itself without one
---@return table<any, true>
function M.set(list, key)
  local out = {}
  for index, item in ipairs(list) do
    out[key_of("set", key, item, index)] = true
  end
  return out
end

--- Keeps the items whose key has not appeared before, in order: the first of
--- each.
---@generic T
---@param list T[]
---@param key? fun(item: T, index: integer): any   -- the item itself without one
---@return T[]
function M.unique(list, key)
  local seen, out = {}, {}
  for index, item in ipairs(list) do
    local found = key_of("unique", key, item, index)
    if not seen[found] then
      seen[found] = true
      out[#out + 1] = item
    end
  end
  return out
end

return require("cds.module").wrap("fp", M)
