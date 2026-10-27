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

return M
