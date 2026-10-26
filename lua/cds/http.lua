---@tag cds.http
---@toc_entry HTTP through curl
---@text
--- Fetch a response without blocking Neovim's event loop. Call request
--- inside a Task or async.run, because the process runner awaits curl.
--- Transport failures (DNS, TLS, timeout, or spawning curl) return nil, err.
--- HTTP 404 and 500 are responses: the caller decides which statuses it accepts
--- before parsing the body. For example: >lua
---
---   local Task = require("cds.task")
---   local http = require("cds.http")
---   local request = Task.new(function()
---     return http.request({ method = "GET", url = "https://example.com/old-feed" })
---   end):ensure(function(response) return response.status == http.status.OK end,
---     function(response) return "HTTP " .. response.status end)
---
---   -- Synchronous script/test; a plugin can observe run:on_complete instead.
---   local response, err = request:run():wait(35000)
---   if err ~= nil then
---     local message = type(err) == "table" and err.message or tostring(err)
---     vim.notify(message, vim.log.levels.ERROR)
---   else
---     -- If /old-feed redirects to /feed.xml, this prints that final URL:
---     -- https://example.com/feed.xml
---     print(response.url)
---     print(response.body)
---   end
--- <
--- The request timeout is in seconds (30 by default); wait takes milliseconds.
--- For a JSON GET, accept 200; a write may instead accept 201 or 204. A 201
--- response may contain a body; 204 has no response content. A 5xx status may
--- justify retrying, but retrying a write needs application-specific care.
--- response.url is curl's effective URL after following redirects; without a
--- redirect it is the requested URL. It is nil when the parsed curl write-out
--- omits the URL or supplies an empty URL, such as older status-only output
--- passed to parse or returned by a test double. Normal successful requests
--- include it. Transport failures return nil, err instead of a Response.
---
--- Options travel on curl's stdin via --config -, so credentials in headers
--- or bodies do not appear in argv. Transfers use compression when offered,
--- and response.body is decoded. The config and parse helpers below support
--- the implementation; request is the normal entry point.

local proc = require("cds.proc")

---@class cds.http
local M = {}

---@class cds.http.Request
---@field method string
---@field url string
---@field headers table<string, string>?
---@field body string?
---@field timeout integer?      -- seconds for curl's --max-time; default 30

---@class cds.http.Response
---@field status integer
---@field headers table<string, string>   -- lower-cased names
---@field body string
---@field url string?                     -- final URL after redirects; nil if absent or empty in curl's write-out

---@class cds.http.Error
---@field kind "unreachable"|"timeout"|"interrupted"|"tls"|"curl"|"spawn"
---@field message string

--- Named response statuses for common branches; OK is 200. The caller chooses
--- which statuses count as success for its operation. transient tests for 5xx.
M.status = {
  OK = 200,
  NOT_MODIFIED = 304,
  UNAUTHORIZED = 401,
  NOT_FOUND = 404,
  CONFLICT = 409,
}

--- Whether a status is the server's trouble (a 5xx), worth trying later.
---@param code integer
---@return boolean
function M.status.transient(code)
  return code >= 500 and code < 600
end

-- A private separator: curl prints it, then the status, after the body.
local MARK = "\n--cds-http-status:"

-- 52, 55 and 56 (empty reply, send failure, receive failure) happen after the
-- request may have left the machine, like a timeout, so they are "interrupted"
-- and the caller treats them as it treats a timeout.
local kinds = {
  [6] = "unreachable",
  [7] = "unreachable",
  [28] = "timeout",
  [35] = "tls",
  [52] = "interrupted",
  [55] = "interrupted",
  [56] = "interrupted",
  [60] = "tls",
}

--- Quotes a value for a curl config file: `"..."` with backslash escapes.
---@param s string
---@return string
function M.quote(s)
  return '"'
    .. s:gsub('[\\"\n\r\t]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" })
    .. '"'
end

--- Writes the config text for a request; exposed for specs.
---@param req cds.http.Request
---@return string
function M.config(req)
  local lines = {
    "silent",
    "show-error",
    -- a moved document is still the document: follow a redirect, a few
    -- at most; the status and headers are the final response's
    "location",
    "max-redirs = 5",
    -- the body arrives gzip or brotli encoded when the server offers it (a
    -- listing page is a fifteenth of its size), and curl decodes it; a
    -- content-length header, when there is one, names the encoded size
    "compressed",
    "dump-header = " .. M.quote("-"),
    "max-time = " .. tostring(req.timeout or 30),
    "write-out = " .. M.quote(MARK .. "%{http_code} %{url_effective}"),
    "request = " .. M.quote(req.method),
    "url = " .. M.quote(req.url),
  }
  for _, name in ipairs(vim.tbl_keys(req.headers or {})) do
    table.insert(lines, "header = " .. M.quote(name .. ": " .. req.headers[name]))
  end
  if req.body then
    -- data-raw: a body starting with "@" is data, where data-binary would
    -- read a file of that name.
    table.insert(lines, "data-raw = " .. M.quote(req.body))
  end
  table.sort(lines)
  return table.concat(lines, "\n") .. "\n"
end

--- Splits curl's stdout (dumped headers, body, then the write-out) into a Response.
---@param out string
---@return cds.http.Response?
function M.parse(out)
  local mark = out:find(MARK, 1, true)
  if not mark then
    return nil
  end
  local code, url = out:sub(mark + #MARK):match("^(%d+)%s*(.-)%s*$")
  local status = tonumber(code)
  local raw = out:sub(1, mark - 1)
  -- Header blocks end at a blank line; a redirect or 100-continue leaves
  -- several blocks, and the last one is the response we want.
  local headers, body = {}, raw
  while true do
    local head, rest = body:match("^(HTTP/[^\r\n]*\r?\n.-\r?\n)\r?\n(.*)$")
    if not head then
      break
    end
    headers = {}
    for name, value in head:gmatch("\n([^:\r\n]+):%s*([^\r\n]*)") do
      headers[name:lower()] = value
    end
    body = rest
  end
  return { status = status, headers = headers, body = body, url = url ~= "" and url or nil }
end

--- Set to a function to be told about every request: { method, url (without
--- its query), status or kind, ms }. Headers and bodies are never passed.
---@type (fun(rec: { method: string, url: string, status: integer?, kind: string?, ms: integer }))?
M.trace = nil

---@param req cds.http.Request
---@return cds.http.Response? response
---@return cds.http.Error? err
local function perform(req)
  local r, spawn_err = proc.run(
    { "curl", "--config", "-" },
    { stdin = M.config(req), timeout = ((req.timeout or 30) + 5) * 1000 }
  )
  if not r then
    return nil, { kind = "spawn", message = spawn_err }
  end
  if r.code ~= 0 then
    local kind = r.timed_out and "timeout" or kinds[r.code] or "curl"
    local detail = vim.trim(r.stderr)
    return nil, { kind = kind, message = ("curl exit %d%s"):format(r.code, detail ~= "" and ": " .. detail or "") }
  end
  local res = M.parse(r.stdout)
  if not res then
    return nil, { kind = "curl", message = "curl produced no status" }
  end
  return res
end

--- Performs the request and answers the response, of any status, or nil and a
--- classified transport error; `trace` is told either way.
---@param req cds.http.Request
---@return cds.http.Response? response
---@return cds.http.Error? err
function M.request(req)
  local started = vim.uv.hrtime()
  local res, err = perform(req)
  if M.trace then
    pcall(M.trace, {
      method = req.method,
      url = (req.url:gsub("[?#].*$", "")),
      status = res and res.status or nil,
      kind = err and err.kind or nil,
      ms = math.floor((vim.uv.hrtime() - started) / 1e6),
    })
  end
  return res, err
end

return require("cds.module").wrap("http", M)
