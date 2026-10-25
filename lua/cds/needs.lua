---@tag cds-lua
---@text
--- cds-lua is a common library for Neovim plugins written in a functional style:
--- `fp` and `result` for the vocabulary, `task` for asynchronous work, and the
--- modules that grew out of the plugins that use them (processes, HTTP,
--- documents, redraws). Each module is pure Lua that names no plugin; every
--- function answers `value` or `nil, err`, and `nil` alone means failure
--- (|cds.result|).
---
--- The library grows by addition: a function keeps its contract under its
--- name, and a different contract gets a different name, so a plugin can
--- declare the functions it uses and run on any commit that has them
--- (|cds.needs|). A name a module does not have fails at the call, in words
--- (|cds.module|).
---
--- This manual covers the modules the plugins call in common. The rest (the
--- document readers, OAuth, processes, dates) are documented in their source,
--- which the language server shows on hover, and on the reference site.
---
---@toc

---@tag cds.needs
---@toc_entry Taking the library
---@text
--- A plugin takes the library as a lazy.nvim dependency, declared in the
--- `lazy.lua` at its root: >lua
---
---   return {
---     "cds-io/<plugin>",
---     dependencies = { { "cds-io/cds-lua", lazy = true } },
---   }
--- <
--- The dependency tracks `main` with no pin, so one `:Lazy update` moves the
--- family together, and one copy of `lua/cds/` is on the runtimepath, so
--- `require("cds.fp")` has one file to resolve to.
---
--- What the plugin calls is declared in `lua/<plugin>/needs.lua`, by module
--- and name: a function, or a table such as `http.status`. >lua
---
---   ---@type cds.needs.Capabilities
---   return {
---     fp = { "map", "filter" },
---     http = { "request", "status" },
---   }
--- <
--- The plugin's entry runs |cds.needs.check()| first and refuses the whole
--- plugin, in one message naming the remedy, when the library installed lacks
--- a name. Its spec harness wraps the declared modules through
--- |cds.needs.strict()|, so a call the declaration leaves out fails the spec
--- in words, and the declaration stays what the code uses.
---
--- The one check a plugin keeps for itself is whether this module loads: a
--- library too old to carry it fails that `require`, which is the answer.

local fp = require("cds.fp")
local module = require("cds.module")

---@class cds.needs
local M = {}

-- The stack as debug.getinfo and error count it from inside a metamethod:
-- level 1 is the metamethod itself, level 2 the function whose `module.name`
-- invoked it, the one a report is about.
local INDEXER = 2

---@alias cds.needs.Capabilities table<string, string[]>  -- cds module to the functions used

--- Lists the modules named, in name order.
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

--- Lists the capabilities the library present lacks, as "fp.filter" names,
--- modules in name order and each in declaration order: a name the module has
--- nothing under, or every name of a module that does not load.
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

--- Answers nil when everything declared is here; otherwise one sentence for the
--- reader, naming the plugin, the missing functions and the remedy.
---@param plugin string  -- truth-table.nvim
---@param capabilities cds.needs.Capabilities
---@return string|nil
function M.check(plugin, capabilities)
  local missing = M.missing(capabilities)
  if #missing == 0 then
    return nil
  end
  return ("%s needs cds-lua with %s: install or update cds-io/cds-lua"):format(plugin, table.concat(missing, ", "))
end

--- Whether a function is one of this library's own: its chunk is a file
--- under lua/cds/. The library's modules use each other beyond any one
--- plugin's declaration, so they pass.
---@param info table|nil  -- debug.getinfo(_, "S") of the function; nil for none
---@return boolean
local function in_library(info)
  return info ~= nil and info.source:find("lua/cds/", 1, true) ~= nil
end

--- Replaces each declared module, in package.loaded, with a proxy that holds
--- nothing itself: a declared name reads from the real module, so a seam a spec
--- replaces there (`proc.runner`) is what the plugin's own code reads; any
--- other name raises, naming the plugin whose declaration is short; a write
--- goes to the real module, since a plugin setting a hook the module leaves nil
--- (`http.trace`) is not declaring a name it reads. The library's own modules
--- pass through, since they use each other beyond the declaration; a module the
--- tier cannot load (one that needs `vim`, under plain busted) is left alone.
--- For a spec harness, before any spec runs.
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
    local allowed = fp.set(capabilities[name], function(fn)
      return fn
    end)
    package.loaded["cds." .. name] = setmetatable({}, {
      __index = function(_, key)
        if not allowed[key] and not in_library(debug.getinfo(INDEXER, "S")) then
          error(("%s uses cds.%s.%s without declaring it in its needs"):format(plugin, name, tostring(key)), INDEXER)
        end
        return real[name][key]
      end,
      __newindex = function(_, key, value)
        real[name][key] = value
      end,
    })
  end)
end

return require("cds.module").wrap("needs", M)
