-- OAuth 2.0 for an installed app: a loopback-redirect login with PKCE, the
-- code exchange, token refresh and revocation. Knows no provider: endpoints,
-- scopes and credentials arrive in `client`.
local async = require("cds.async")

local M = {}

--- The HTTP module; specs replace it.
M.http = require("cds.http")
local status = M.http.status

---@class cds.oauth.Client
---@field id string
---@field secret string
---@field auth_url string
---@field token_url string
---@field revoke_url string?
---@field scopes string[]

---@class cds.oauth.TokenSet
---@field access_token string?
---@field refresh_token string?
---@field expires_at integer      -- epoch seconds
---@field scope string?

---@class cds.oauth.Error
---@field kind string
---@field message string

--- application/x-www-form-urlencoded; vim.uri_encode leaves `&`, `=` and `+` alone.
---@param params table<string, string>
---@return string
function M.form(params)
  local parts = {}
  for name, value in vim.spairs(params) do
    local encode = function(s)
      return (s:gsub("[^%w%-%._~]", function(c)
        return ("%%%02X"):format(c:byte())
      end))
    end
    parts[#parts + 1] = encode(name) .. "=" .. encode(value)
  end
  return table.concat(parts, "&")
end

---@param query string
---@return table<string, string>
function M.parse_query(query)
  local params = {}
  for pair in query:gmatch("[^&]+") do
    local name, value = pair:match("^([^=]*)=?(.*)$")
    params[vim.uri_decode(name)] = vim.uri_decode(value)
  end
  return params
end

---@param s string
---@return string
local function b64url(s)
  return (vim.base64.encode(s):gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

---@param s string
---@return string
local function sha256(s)
  return (vim.text.hexdecode(vim.fn.sha256(s)))
end

--- PKCE verifier and S256 challenge; exposed for specs.
---@return string verifier
---@return string challenge
function M.pkce()
  local verifier = b64url(vim.uv.random(32))
  return verifier, b64url(sha256(verifier))
end

---@param body string
---@return table?
local function decode(body)
  local ok, value = pcall(vim.json.decode, body)
  return ok and type(value) == "table" and value or nil
end

--- Turns a token endpoint response into a TokenSet or an error.
---@param res cds.http.Response?
---@param err cds.http.Error?
---@param now integer
---@return cds.oauth.TokenSet? set
---@return cds.oauth.Error? err
function M.token_response(res, err, now)
  if not res then
    return nil, { kind = err.kind, message = err.message }
  end
  local body = decode(res.body) or {}
  if res.status ~= status.OK then
    local kind = body.error == "invalid_grant" and "invalid_grant" or "token_endpoint"
    local message = body.error_description or body.error or ("HTTP %d"):format(res.status)
    return nil, { kind = kind, message = message }
  end
  if type(body.access_token) ~= "string" then
    return nil, { kind = "token_endpoint", message = "no access_token in the response" }
  end
  return {
    access_token = body.access_token,
    refresh_token = body.refresh_token,
    expires_at = now + (tonumber(body.expires_in) or 3600),
    scope = body.scope,
  }
end

---@param client cds.oauth.Client
---@param params table<string, string>
---@param now integer?             -- epoch seconds; injectable for specs
---@return cds.oauth.TokenSet? set
---@return cds.oauth.Error? err
local function post_token(client, params, now)
  params.client_id = client.id
  params.client_secret = client.secret
  local res, err = M.http.request({
    method = "POST",
    url = client.token_url,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = M.form(params),
  })
  return M.token_response(res, err, now or os.time())
end

--- Waits for the browser's redirect on `server` and returns its query string.
---@param server uv.uv_tcp_t
---@return table<string, string>
local function await_redirect(server)
  local page = "<!doctype html><title>calplus</title><p>Signed in. You can close this tab.</p>"
  local response = table.concat({
    "HTTP/1.1 200 OK",
    "Content-Type: text/html",
    "Content-Length: " .. #page,
    "Connection: close",
    "",
    page,
  }, "\r\n")
  -- libuv callbacks run in a fast event context; resume on the main loop.
  local line = async.await(1, function(resume)
    local cb = vim.schedule_wrap(resume)
    server:listen(16, function(err)
      if err then
        return cb(nil, err)
      end
      local sock = vim.uv.new_tcp()
      server:accept(sock)
      local buf = ""
      sock:read_start(function(rerr, chunk)
        if rerr or not chunk then
          return sock:close()
        end
        buf = buf .. chunk
        local first = buf:match("^([^\r\n]*)\r?\n")
        if first then
          sock:read_stop()
          sock:write(response, function()
            sock:close()
          end)
          cb(first)
        end
      end)
    end)
  end)
  local query = line and line:match("^GET /%?([^ ]*)") or ""
  return M.parse_query(query)
end

---@class cds.oauth.LoginOpts
---@field open fun(url: string)      -- shows the authorization URL to the user
---@field timeout integer?           -- ms to wait for the browser; default 120000

--- One interactive login. Returns the token set, or nil and an error whose
--- kind is "timeout", "denied", "state", "listen" or a token endpoint kind.
---@param client cds.oauth.Client
---@param opts cds.oauth.LoginOpts
---@return cds.oauth.TokenSet? set
---@return cds.oauth.Error? err
function M.login(client, opts)
  local server = vim.uv.new_tcp()
  local ok, bind_err = pcall(server.bind, server, "127.0.0.1", 0)
  if not ok then
    server:close()
    return nil, { kind = "listen", message = tostring(bind_err) }
  end
  local redirect_uri = ("http://127.0.0.1:%d/"):format(server:getsockname().port)
  local state = b64url(vim.uv.random(16))
  local verifier, challenge = M.pkce()
  opts.open(client.auth_url .. "?" .. M.form({
    client_id = client.id,
    redirect_uri = redirect_uri,
    response_type = "code",
    scope = table.concat(client.scopes, " "),
    access_type = "offline",
    prompt = "consent",
    state = state,
    code_challenge = challenge,
    code_challenge_method = "S256",
  }))
  -- The wait runs as a child task so async.timeout can bound it; a child's
  -- error fails the parent through any pcall, so the child catches its own.
  local waited, params, wait_err = pcall(
    async.timeout,
    opts.timeout or 120000,
    async.run(function()
      local caught, result = pcall(await_redirect, server)
      if not caught then
        return nil, { kind = "internal", message = tostring(result) }
      end
      return result
    end)
  )
  -- When the child finishes before the deadline, async.timeout resumes its
  -- caller from the timer's teardown, a fast event context where vim.env,
  -- vim.fn and the API raise E5560. Hop back to the main loop.
  if vim.in_fast_event() then
    async.await(1, vim.schedule)
  end
  server:close()
  if not waited then
    return nil, { kind = "timeout", message = "no response from the browser" }
  elseif not params then
    return nil, wait_err
  end
  if params.error then
    return nil, { kind = "denied", message = params.error }
  elseif params.state ~= state or type(params.code) ~= "string" then
    return nil, { kind = "state", message = "the redirect did not match this login" }
  end
  return post_token(client, {
    grant_type = "authorization_code",
    code = params.code,
    code_verifier = verifier,
    redirect_uri = redirect_uri,
  })
end

---@param client cds.oauth.Client
---@param refresh_token string
---@param now integer?
---@return cds.oauth.TokenSet? set
---@return cds.oauth.Error? err
function M.refresh(client, refresh_token, now)
  return post_token(client, { grant_type = "refresh_token", refresh_token = refresh_token }, now)
end

--- Best effort: the caller clears its store whatever this returns.
---@param client cds.oauth.Client
---@param token string
---@return boolean ok
---@return string? err
function M.revoke(client, token)
  if not client.revoke_url then
    return true
  end
  local res, err = M.http.request({
    method = "POST",
    url = client.revoke_url,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = M.form({ token = token }),
  })
  if not res then
    return false, err.message
  elseif res.status ~= status.OK then
    return false, ("HTTP %d"):format(res.status)
  end
  return true
end

---@param opts cds.oauth.SessionOpts
---@return cds.oauth.Session
function M.session(opts)
  return require("cds.oauth.session").new(opts)
end

return M
