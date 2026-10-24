-- Secret storage behind one small contract. `get` has three answers, and the
-- difference between the last two is what keeps a locked store from being
-- mistaken for "no credentials":
--   value        present
--   nil, nil     absent
--   nil, message the backend could not answer
local M = {}

---@class cds.secrets.Store
---@field get async fun(name: string): string?, string?
---@field set async fun(name: string, value: string): boolean?, string?
---@field delete async fun(name: string): boolean?, string?

---@class cds.secrets.Spec
---@field backend "os-key-store"|"op"
---@field service string          -- namespace for item names
---@field vault string?           -- required by "op"
---@field platform string?        -- injectable for specs; defaults to jit.os

--- Backends by name; specs may add one.
M.backends = {
  ["os-key-store"] = function(spec)
    local platform = spec.platform or jit.os
    if platform ~= "OSX" then
      return nil, "no OS key store backend on this platform; set security = { backend = 'op', vault = ... }"
    end
    return require("cds.secrets.keychain").open(spec)
  end,
  op = function(spec)
    if type(spec.vault) ~= "string" or spec.vault == "" then
      return nil, "the op backend needs a vault: security = { backend = 'op', vault = 'Private' }"
    end
    return require("cds.secrets.op").open(spec)
  end,
}

---@param spec cds.secrets.Spec
---@return cds.secrets.Store? store
---@return string? err
function M.open(spec)
  local backend = M.backends[spec.backend]
  if not backend then
    return nil, ("unknown secret backend %q"):format(tostring(spec.backend))
  end
  if type(spec.service) ~= "string" or spec.service == "" then
    return nil, "secrets.open needs a service name"
  end
  return backend(spec)
end

return M
