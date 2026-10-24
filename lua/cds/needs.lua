-- What a plugin needs from this library, checked against the copy present.
-- A plugin declares the functions it uses, by module (`{ fp = { "map",
-- "filter" } }`), and asks at startup whether they are here; the answer is
-- the names that are not, or a sentence for the reader naming them and the
-- remedy. The library grows by addition, so a plugin runs on any commit that
-- has what it declares, and the declaration is the plugin's statement of
-- that. `strict` is for a plugin's specs: the declared modules behind proxies
-- that refuse any other name, so the declaration stays what the code uses.
--
-- The one check a plugin keeps for itself is whether this module loads: a
-- library too old to carry it fails that `require`, which is the answer.
local M = {}

---@alias cds.needs.Capabilities table<string, string[]>  -- cds module to the functions used

--- The modules named, in name order.
---@param capabilities cds.needs.Capabilities
---@return string[]
local function modules(capabilities)
  local names = {}
  for name in pairs(capabilities) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- The capabilities the library present lacks, as "fp.filter" names,
--- modules in name order and each in declaration order; a module that does
--- not load counts every name of it.
---@param capabilities cds.needs.Capabilities
---@return string[]
function M.missing(capabilities)
  local out = {}
  for _, name in ipairs(modules(capabilities)) do
    local ok, mod = pcall(require, "cds." .. name)
    for _, fn in ipairs(capabilities[name]) do
      if not (ok and type(mod) == "table" and type(mod[fn]) == "function") then
        out[#out + 1] = name .. "." .. fn
      end
    end
  end
  return out
end

--- nil when everything declared is here; otherwise one sentence for the
--- reader, naming the plugin, the missing functions and the remedy.
---@param plugin string  -- truth-table.nvim
---@param capabilities cds.needs.Capabilities
---@return string|nil
function M.check(plugin, capabilities)
  local missing = M.missing(capabilities)
  if #missing == 0 then
    return nil
  end
  return ("%s needs cds-lua with %s: install cds-io/cds-lua at the commit lazy.lua pins, or update it"):format(
    plugin,
    table.concat(missing, ", ")
  )
end

--- Each declared module replaced, in package.loaded, by a proxy that answers
--- the declared functions and raises on any other name, naming the plugin
--- whose declaration is short. Every declared module is required for real
--- first, so a module that uses another internally keeps the real one.
--- For a spec harness, before any spec runs.
---@param plugin string
---@param capabilities cds.needs.Capabilities
function M.strict(plugin, capabilities)
  local real = {}
  for name in pairs(capabilities) do
    real[name] = require("cds." .. name)
  end
  for name, fns in pairs(capabilities) do
    local allowed = {}
    for _, fn in ipairs(fns) do
      allowed[fn] = true
    end
    package.loaded["cds." .. name] = setmetatable({}, {
      __index = function(_, key)
        if not allowed[key] then
          error(("%s uses cds.%s.%s without declaring it in its needs"):format(plugin, name, tostring(key)), 2)
        end
        return real[name][key]
      end,
    })
  end
end

return M
