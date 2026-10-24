-- An append-only log file: one JSON object per line, always starting with the
-- time, the level and the event name so a line reads left to right before it
-- is parsed. Writes are synchronous and go through vim.uv alone, so a record
-- can be written from any context, a libuv callback included.
--
-- The logger records what it is given. Keeping secrets out is the caller's
-- job: pass names and outcomes, never headers, bodies or tokens.
local M = {}

local LEVELS = { off = 0, info = 1, debug = 2 }

---@class cds.Log
---@field path string
---@field level "off"|"info"|"debug"
local Log = {}
Log.__index = Log

---@param fields table
---@return string
local function encode(fields)
  if next(fields) == nil then
    return "{}" -- vim.json would write an empty table as []
  end
  local ok, text = pcall(vim.json.encode, fields)
  if ok then
    return text
  end
  return vim.json.encode({ unencodable = vim.inspect(fields) })
end

---@param level "info"|"debug"
---@param event string
---@param fields table?
---@return boolean written   -- false only when the file could not be written
function Log:write(level, event, fields)
  if LEVELS[level] > (LEVELS[self.level] or 0) then
    return true
  end
  local line = ('{"t":%s,"level":%s,"event":%s,"fields":%s}\n'):format(
    vim.json.encode(os.date("%Y-%m-%dT%H:%M:%S")),
    vim.json.encode(level),
    vim.json.encode(event),
    encode(fields or {})
  )
  local fd = vim.uv.fs_open(self.path, "a", 420) -- 0644
  if not fd then
    return false
  end
  local wrote = vim.uv.fs_write(fd, line)
  vim.uv.fs_close(fd)
  return wrote ~= nil
end

---@param event string
---@param fields table?
---@return boolean
function Log:info(event, fields)
  return self:write("info", event, fields)
end

---@param event string
---@param fields table?
---@return boolean
function Log:debug(event, fields)
  return self:write("debug", event, fields)
end

--- Call this on the main loop: it creates the directory with vim.fn.
---@param opts { path: string, level: "off"|"info"|"debug"? }
---@return cds.Log
function M.new(opts)
  local level = opts.level or "info"
  if level ~= "off" then
    pcall(vim.fn.mkdir, vim.fs.dirname(opts.path), "p")
  end
  return setmetatable({ path = opts.path, level = level }, Log)
end

return M
