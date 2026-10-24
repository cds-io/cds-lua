-- What a plugin needs from this library, checked against the copy present.
-- A plugin declares the names it uses, by module (`{ fp = { "map", "filter"
-- } }`, a function or a table such as `http.status`), and asks at startup
-- whether they are here; the answer is
-- the names that are not, or a sentence for the reader naming them and the
-- remedy. The library grows by addition, so a plugin runs on any commit that
-- has what it declares, and the declaration is the plugin's statement of
-- that. `strict` is for a plugin's specs: the declared modules behind proxies
-- that refuse any other name, so the declaration stays what the code uses.
--
-- The one check a plugin keeps for itself is whether this module loads: a
-- library too old to carry it fails that `require`, which is the answer.
local fp = require("cds.fp")
local module = require("cds.module")

local M = {}

-- The stack as debug.getinfo and error count it from inside a metamethod:
-- level 1 is the metamethod itself, level 2 the function whose `module.name`
-- invoked it, the one a report is about.
local INDEXER = 2

---@alias cds.needs.Capabilities table<string, string[]>  -- cds module to the functions used

--- The modules named, in name order.
---@param capabilities cds.needs.Capabilities
---@return string[]
local function modules(capabilities)
  local names = fp.keys(capabilities)
  table.sort(names)
  return names
end

--- Whether the module has something under the name: a lookup that answers
--- nothing, or answers the library's own fallback for a missing name
--- (cds.module), is a name it lacks.
---@param mod table
---@param fn string
---@return boolean
local function has(mod, fn)
  local value = mod[fn]
  return value ~= nil and not module.is_fallback(value)
end

--- The capabilities the library present lacks, as "fp.filter" names,
--- modules in name order and each in declaration order: a name the module
--- has nothing under, or every name of a module that does not load.
---@param capabilities cds.needs.Capabilities
---@return string[]
function M.missing(capabilities)
  return fp.flat_map(modules(capabilities), function(name)
    local ok, mod = pcall(require, "cds." .. name)
    local lacking = fp.filter(capabilities[name], function(fn)
      return not (ok and type(mod) == "table" and has(mod, fn))
    end)
    return fp.map(lacking, function(fn)
      return name .. "." .. fn
    end)
  end)
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

--- Whether a function is one of this library's own: its chunk is a file
--- under lua/cds/. The library's modules use each other beyond any one
--- plugin's declaration, so they pass.
---@param info table|nil  -- debug.getinfo(_, "S") of the function; nil for none
---@return boolean
local function in_library(info)
  return info ~= nil and info.source:find("lua/cds/", 1, true) ~= nil
end

--- Each declared module replaced, in package.loaded, by a proxy that holds
--- the declared names the module has (so `missing` reads them as present)
--- and raises on any other, naming the plugin whose declaration is short.
--- The library's own modules pass through, since they use each other beyond
--- the declaration; a module the tier cannot load (one that needs `vim`,
--- under plain busted) is left alone. For a spec harness, before any spec
--- runs.
---@param plugin string
---@param capabilities cds.needs.Capabilities
function M.strict(plugin, capabilities)
  local real = {}
  fp.each(modules(capabilities), function(name)
    local ok, mod = pcall(require, "cds." .. name)
    if ok then
      real[name] = mod
    end
  end)
  local present = fp.filter(modules(capabilities), function(name)
    return real[name] ~= nil
  end)
  fp.each(present, function(name)
    local proxy = {}
    fp.each(capabilities[name], function(fn)
      if has(real[name], fn) then
        proxy[fn] = real[name][fn]
      end
    end)
    package.loaded["cds." .. name] = setmetatable(proxy, {
      __index = function(_, key)
        if not in_library(debug.getinfo(INDEXER, "S")) then
          error(("%s uses cds.%s.%s without declaring it in its needs"):format(plugin, name, tostring(key)), INDEXER)
        end
        return real[name][key]
      end,
    })
  end)
end

return require("cds.module")("needs", M)
