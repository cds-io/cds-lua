-- The macOS keychain through /usr/bin/security. Commands go to `security -i`
-- on stdin, so the value never reaches argv, and the value is hex (-X)
-- because the interactive parser tokenises on whitespace and rejects a quoted
-- JSON string. Exit 44 is "item not found".
local proc = require("cds.proc")

local M = {}

local NOT_FOUND = 44

---@param r cds.proc.Result
---@return string
local function message(r)
  local text = vim.trim(r.stderr ~= "" and r.stderr or r.stdout)
  return ("security exit %d%s"):format(r.code, text ~= "" and ": " .. text or "")
end

---@param spec cds.secrets.Spec
---@return cds.secrets.Store
function M.open(spec)
  local service = spec.service
  local store = {}

  function store.get(name)
    local r, err = proc.run(
      { "security", "find-generic-password", "-a", name, "-s", service, "-w" },
      { timeout = 30000 }
    )
    if not r then
      return nil, err
    elseif r.code == NOT_FOUND then
      return nil, nil
    elseif r.code ~= 0 then
      return nil, message(r)
    end
    return (r.stdout:gsub("\n$", ""))
  end

  function store.set(name, value)
    local line = ("add-generic-password -a %s -s %s -U -X %s\n"):format(
      name,
      service,
      vim.text.hexencode(value):lower()
    )
    local r, err = proc.run({ "security", "-i" }, { stdin = line, timeout = 30000 })
    if not r then
      return nil, err
    elseif r.code ~= 0 then
      return nil, message(r)
    end
    return true
  end

  function store.delete(name)
    local r, err = proc.run({ "security", "delete-generic-password", "-a", name, "-s", service }, { timeout = 30000 })
    if not r then
      return nil, err
    elseif r.code ~= 0 and r.code ~= NOT_FOUND then
      return nil, message(r)
    end
    return true
  end

  return store
end

return require("cds.module")("secrets.keychain", M)
