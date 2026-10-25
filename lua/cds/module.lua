---@tag cds.module
---@toc_entry Names a module does not have
---@text
--- Every module of the library returns through |cds.module.wrap()|, so a
--- name a module does not have fails at the call with the module's name and
--- the key in words, where plain Lua says "attempt to call field 'filter_mop'
--- (a nil value)" somewhere later. The usual cause is a cds-lua older than the
--- code calling it, and the message says so.
---
--- A lookup on a module therefore answers a function for every name. A test
--- for a name's presence asks |cds.module.is_fallback()| of what the lookup
--- answered, as cds.needs does; `rawget` would miss a module whose names come
--- through a metatable of its own, as vim.async's do.
---
--- A module ends with >lua
---
---   return require("cds.module").wrap("fp", M)
--- <
--- and declares `---@class cds.fp` above its table, so the language server
--- carries the module's type to every caller and a misspelt name is an
--- undefined field at edit time. The named function is the form: a `__call`
--- metamethod in its place loses the type.
---@class cds.module
local M = {}

-- every fallback handed out, weakly, so is_fallback knows them
local fallbacks = setmetatable({}, { __mode = "k" })

--- Puts the fallback behind the module and answers the module.
---@generic T: table
---@param name string  -- "fp", "html.blocks"
---@param mod T
---@return T
function M.wrap(name, mod)
  return setmetatable(mod, {
    __index = function(_, key)
      local fallback = function()
        error(
          ("cds.%s has no %q: the cds-lua installed is older than this code needs, or the name is misspelt"):format(
            name,
            tostring(key)
          ),
          2
        )
      end
      fallbacks[fallback] = true
      return fallback
    end,
  })
end

--- Whether a value is one of the fallbacks: what a module answered for a
--- name it does not have.
---@param value any
---@return boolean
function M.is_fallback(value)
  return fallbacks[value] == true
end

-- `return require("cds.module").wrap(name, M)` is the form every module ends
-- with. The call goes through the named function because the language server
-- carries `wrap`'s generic (the module's own type comes back out) and loses it
-- through a `__call` metamethod, where the result is unknown to every caller.
return M
