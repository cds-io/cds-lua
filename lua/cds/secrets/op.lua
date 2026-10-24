-- The 1Password CLI. One item per secret, titled "<service>-<name>", category
-- PASSWORD, value in the `password` field. Writes send the item as a JSON
-- template on stdin (the `-` argument); `op` refuses `--template=/dev/stdin`.
-- Every failure exits 1, so absence is recognised from the message text.
local proc = require("cds.proc")

local M = {}

-- op 2.39 words absence two ways: `read` and `delete` say `"<title>" isn't an
-- item in the "<vault>" vault.`, while `edit` says `could not find item to edit`.
local ABSENT = { "isn't an item", "could not find item" }

---@param r cds.proc.Result
---@return boolean
local function absent(r)
  for _, needle in ipairs(ABSENT) do
    if r.stderr:find(needle, 1, true) then
      return true
    end
  end
  return false
end

---@param r cds.proc.Result
---@return string
local function message(r)
  local text = vim.trim(r.stderr ~= "" and r.stderr or r.stdout):gsub("^%[ERROR%] [%d/]+ [%d:]+ ", "")
  return ("op exit %d%s"):format(r.code, text ~= "" and ": " .. text or "")
end

---@param title string
---@param value string
---@return string
function M.template(title, value)
  return vim.json.encode({
    title = title,
    category = "PASSWORD",
    fields = { { id = "password", type = "CONCEALED", purpose = "PASSWORD", label = "password", value = value } },
  })
end

---@param spec cds.secrets.Spec
---@return cds.secrets.Store
function M.open(spec)
  local vault = spec.vault
  local store = {}

  local function title(name)
    return spec.service .. "-" .. name
  end

  function store.get(name)
    local ref = ("op://%s/%s/password"):format(vault, title(name))
    local r, err = proc.run({ "op", "read", "--no-newline", ref }, { timeout = 60000 })
    if not r then
      return nil, err
    elseif r.code ~= 0 and absent(r) then
      return nil, nil
    elseif r.code ~= 0 then
      return nil, message(r)
    end
    return r.stdout
  end

  -- Edit first, create only when absent: titles are not unique in 1Password,
  -- and a second item with this title would break every later read.
  function store.set(name, value)
    local body = M.template(title(name), value) .. "\n"
    local r, err = proc.run(
      { "op", "item", "edit", title(name), "--vault", vault, "-" },
      { stdin = body, timeout = 60000 }
    )
    if not r then
      return nil, err
    elseif r.code == 0 then
      return true
    elseif not absent(r) then
      return nil, message(r)
    end
    r, err = proc.run({ "op", "item", "create", "--vault", vault, "-" }, { stdin = body, timeout = 60000 })
    if not r then
      return nil, err
    elseif r.code ~= 0 then
      return nil, message(r)
    end
    return true
  end

  function store.delete(name)
    local r, err = proc.run({ "op", "item", "delete", title(name), "--vault", vault }, { timeout = 60000 })
    if not r then
      return nil, err
    elseif r.code ~= 0 and not absent(r) then
      return nil, message(r)
    end
    return true
  end

  return store
end

return M
