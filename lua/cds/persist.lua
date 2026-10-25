---@tag cds.persist
---@toc_entry File and JSON persistence
---@text
--- Read and write plugin state without owning the caller's model or save
--- schedule. Every operation returns a value or nil, err. Writes create parent
--- directories and replace the destination through a temporary file beside it,
--- so an encoding or write failure leaves the previous file intact.
---
--- >lua
---   local persist = require("cds.persist")
---   local path = vim.fn.stdpath("data") .. "/example/settings.json"
---   local ok, err = persist.save_json(path, { enabled = true })
---   if not ok then vim.notify(err, vim.log.levels.ERROR) end
---   local settings, read_err = persist.load_json(path)
--- <
--- Missing or malformed files are errors; the plugin chooses its fallback.
--- JSON may decode to any JSON value, including false: callers validate their
--- own schema. These functions perform synchronous local file I/O.

---@class cds.persist
local M = {}

--- Read the complete file as bytes.
---@param path string
---@return string? content
---@return string? err
function M.read(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, path .. ": " .. tostring(err)
  end
  local content, read_err = file:read("*a")
  local closed, close_err = file:close()
  if not content or not closed then
    return nil, path .. ": " .. tostring(read_err or close_err)
  end
  return content
end

--- Atomically replace a file's contents. Parent directories are created.
---@param path string
---@param content string
---@return true? saved
---@return string? err
function M.write(path, content)
  local ok, mkdir_err = pcall(vim.fn.mkdir, vim.fn.fnamemodify(path, ":h"), "p")
  if not ok then
    return nil, path .. ": " .. tostring(mkdir_err)
  end
  local fd, temporary = vim.uv.fs_mkstemp(path .. ".XXXXXX")
  if not fd then
    return nil, path .. ": " .. tostring(temporary)
  end
  local offset, failure = 0, nil
  while offset < #content do
    local written, err = vim.uv.fs_write(fd, content:sub(offset + 1), offset)
    if not written or written == 0 then
      failure = err or "short write"
      break
    end
    offset = offset + written
  end
  local closed, close_err = vim.uv.fs_close(fd)
  if not closed then
    failure = failure or close_err
  end
  if not failure then
    local renamed, rename_err = vim.uv.fs_rename(temporary, path)
    if not renamed then
      failure = rename_err
    end
  end
  if failure then
    vim.uv.fs_unlink(temporary)
    return nil, path .. ": " .. tostring(failure)
  end
  return true
end

--- Atomically write a list of lines with writefile's newline semantics.
--- Each item ends with a newline; an empty list writes an empty file. Embedded
--- newlines inside an item become NUL bytes, as with vim.fn.writefile.
---@param path string
---@param lines string[]
---@return true? saved
---@return string? err
function M.write_lines(path, lines)
  local encoded = {}
  for i, line in ipairs(lines) do
    encoded[i] = (line:gsub("\n", "\0"))
  end
  return M.write(path, table.concat(encoded, "\n") .. (#lines > 0 and "\n" or ""))
end

--- Encode before touching disk, then atomically save the JSON value.
---@param path string
---@param value any
---@return true? saved
---@return string? err
function M.save_json(path, value)
  local ok, content = pcall(vim.json.encode, value)
  if not ok then
    return nil, path .. ": cannot encode JSON: " .. tostring(content)
  end
  return M.write(path, content)
end

--- Load a JSON value; schema validation belongs to the caller.
---@param path string
---@return any value
---@return string? err
function M.load_json(path)
  local content, err = M.read(path)
  if content == nil then
    return nil, err
  end
  local ok, value = pcall(vim.json.decode, content)
  if not ok then
    return nil, path .. ": cannot parse JSON: " .. tostring(value)
  end
  return value
end

return require("cds.module").wrap("persist", M)
