-- A replacement for cds.http.request: answers from a script and records
-- every request. `script` is a list of { match, response } where `match` is a
-- string found in the URL (or a function(req) → boolean) and `response` is
-- { status, body, headers } or { err = { kind, message } } or a function(req).
local M = {}

---@param script table[]
---@return table module   -- { request = fun(req) }
function M.new(script)
  local fake = { calls = {} }
  function fake.request(req)
    table.insert(fake.calls, vim.deepcopy(req))
    for _, s in ipairs(script) do
      local hit
      if type(s.match) == "function" then
        hit = s.match(req)
      else
        hit = req.url:find(s.match, 1, true)
      end
      if hit then
        local r = type(s.response) == "function" and s.response(req) or s.response
        if r.err then
          return nil, r.err
        end
        return { status = r.status or 200, headers = r.headers or {}, body = r.body or "" }
      end
    end
    error(("fakehttp: no script matches %s %s"):format(req.method, req.url))
  end
  return fake
end

--- An in-memory cds.secrets.Store, with an optional `fail` message that
--- makes every call answer nil, fail.
---@return table store
function M.store()
  local store = { items = {}, fail = nil }
  function store.get(name)
    if store.fail then
      return nil, store.fail
    end
    return store.items[name], nil
  end
  function store.set(name, value)
    if store.fail then
      return nil, store.fail
    end
    store.items[name] = value
    return true
  end
  function store.delete(name)
    if store.fail then
      return nil, store.fail
    end
    store.items[name] = nil
    return true
  end
  return store
end

return M
