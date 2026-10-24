-- A session holds one token set for one client and applies the two rules a
-- refresh needs: it runs once no matter how many callers arrive while it is
-- in flight, and stored credentials are cleared only when the server says
-- `invalid_grant`. Anything else (offline, a 500, a locked store) is reported
-- and leaves them in place.
local async = require("cds.async")

---@class cds.oauth.SessionOpts
---@field client cds.oauth.Client
---@field store cds.secrets.Store
---@field name string                 -- item name in the store
---@field now (fun(): integer)?       -- injectable clock

---@class cds.oauth.Session
---@field private client cds.oauth.Client
---@field private store cds.secrets.Store
---@field private name string
---@field private now fun(): integer
---@field private set cds.oauth.TokenSet?
---@field private loaded boolean
---@field private refreshing vim.async.Task?
local Session = {}
Session.__index = Session

---@class cds.oauth.session
local M = {}

-- Seconds of remaining life below which the access token is refreshed early.
local SLACK = 60

---@param opts cds.oauth.SessionOpts
---@return cds.oauth.Session
function M.new(opts)
  return setmetatable({
    client = opts.client,
    store = opts.store,
    name = opts.name,
    now = opts.now or os.time,
    set = nil,
    loaded = false,
  }, Session)
end

---@private
---@return boolean ok
---@return cds.oauth.Error? err
function Session:load()
  if self.loaded then
    return true
  end
  local raw, err = self.store.get(self.name)
  if err then
    return false, { kind = "store", message = err }
  end
  if raw then
    local ok, set = pcall(vim.json.decode, raw)
    if ok and type(set) == "table" then
      self.set = set
    end
  end
  self.loaded = true
  return true
end

--- Are credentials stored? Reads the store; never the network.
---@return boolean present
---@return cds.oauth.Error? err
function Session:present()
  local ok, err = self:load()
  if not ok then
    return false, err
  end
  return self.set ~= nil and self.set.refresh_token ~= nil
end

---@param set cds.oauth.TokenSet
---@return boolean ok
---@return cds.oauth.Error? err
function Session:save(set)
  self.set, self.loaded = set, true
  local ok, err = self.store.set(self.name, vim.json.encode(set))
  if not ok then
    return false, { kind = "store", message = err }
  end
  return true
end

---@return boolean ok
---@return cds.oauth.Error? err
function Session:clear()
  self.set, self.loaded = nil, true
  local ok, err = self.store.delete(self.name)
  if not ok then
    return false, { kind = "store", message = err }
  end
  return true
end

--- The stored token set, for a caller that revokes before clearing.
---@return cds.oauth.TokenSet? set
---@return cds.oauth.Error? err
function Session:get()
  local ok, err = self:load()
  if not ok then
    return nil, err
  end
  return self.set
end

--- Drops the cached access token; the next token() refreshes.
function Session:invalidate()
  if self.set then
    self.set.access_token = nil
  end
end

---@private
---@return string? token
---@return cds.oauth.Error? err
function Session:do_refresh()
  local oauth = require("cds.oauth")
  local fresh, err = oauth.refresh(self.client, self.set.refresh_token, self.now())
  if not fresh then
    assert(err, "a refused refresh carries its error")
    if err.kind == "invalid_grant" then
      self:clear()
      return nil, { kind = "revoked", message = err.message }
    elseif err.kind == "unreachable" or err.kind == "timeout" then
      return nil, err
    end
    return nil, { kind = "refresh_failed", message = err.message }
  end
  fresh.refresh_token = fresh.refresh_token or self.set.refresh_token
  local saved, save_err = self:save(fresh)
  if not saved then
    return nil, save_err
  end
  return fresh.access_token
end

--- A bearer token, refreshing when fewer than SLACK seconds remain.
---@return string? token
---@return cds.oauth.Error? err
function Session:token()
  local ok, err = self:load()
  if not ok then
    return nil, err
  end
  if not self.set or not self.set.refresh_token then
    return nil, { kind = "no_credentials", message = "no stored credentials" }
  end
  if self.set.access_token and (self.set.expires_at or 0) - self.now() > SLACK then
    return self.set.access_token
  end
  -- A child task's error fails every task awaiting it, and pcall around the
  -- await does not contain it, so the refresh catches its own errors.
  if not self.refreshing then
    self.refreshing = async.run(function()
      local caught, token, rerr = pcall(self.do_refresh, self)
      self.refreshing = nil
      if not caught then
        return nil, { kind = "refresh_failed", message = tostring(token) }
      end
      return token, rerr
    end)
  end
  return async.await(self.refreshing)
end

return require("cds.module").wrap("oauth.session", M)
