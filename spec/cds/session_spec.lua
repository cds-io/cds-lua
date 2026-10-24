local async = require("cds.async")
local fakehttp = require("fakehttp")
local oauth = require("cds.oauth")

local client = { id = "cid", secret = "csecret", token_url = "https://auth.test/token", scopes = {} }

describe("cds.oauth.session", function()
  local original_http, store, clock
  before_each(function()
    original_http = oauth.http
    store = fakehttp.store()
    clock = 1000
  end)
  after_each(function()
    oauth.http = original_http
  end)

  local function session()
    return oauth.session({
      client = client,
      store = store,
      name = "google",
      now = function()
        return clock
      end,
    })
  end

  local function stored(set)
    store.items.google = vim.json.encode(set)
  end

  local function run(fn)
    return async.run(fn):wait(1000)
  end

  local function refresh_ok(body)
    oauth.http =
      fakehttp.new({ { match = "/token", response = { body = body or '{"access_token":"new","expires_in":3600}' } } })
  end

  it("reports no credentials when the store is empty, and a store error apart", function()
    local token, err = run(function()
      return session():token()
    end)
    assert.is_nil(token)
    assert.are.equal("no_credentials", err.kind)
    store.fail = "locked"
    token, err = run(function()
      return session():token()
    end)
    assert.is_nil(token)
    assert.are.same({ "store", "locked" }, { err.kind, err.message })
    local present, perr = run(function()
      return session():present()
    end)
    assert.is_false(present)
    assert.are.equal("store", perr.kind)
  end)

  it("returns the stored access token while more than a minute remains", function()
    stored({ access_token = "at", refresh_token = "rt", expires_at = clock + 61 })
    oauth.http = fakehttp.new({})
    assert.are.equal(
      "at",
      run(function()
        return session():token()
      end)
    )
    assert.are.same({}, oauth.http.calls)
  end)

  it("refreshes once for concurrent callers and stores the merged set", function()
    stored({ access_token = "at", refresh_token = "rt", expires_at = clock + 30 })
    oauth.http = fakehttp.new({
      {
        match = "/token",
        response = function()
          async.sleep(20)
          return { body = '{"access_token":"new","expires_in":3600}' }
        end,
      },
    })
    local s = session()
    local tokens = run(function()
      local a = async.run(s.token, s)
      local b = async.run(s.token, s)
      return { async.await(a), async.await(b) }
    end)
    assert.are.same({ "new", "new" }, tokens)
    assert.are.equal(1, #oauth.http.calls)
    local form = oauth.parse_query(oauth.http.calls[1].body)
    assert.are.same({ "refresh_token", "rt", "cid", "csecret" }, {
      form.grant_type,
      form.refresh_token,
      form.client_id,
      form.client_secret,
    })
    local saved = vim.json.decode(store.items.google)
    assert.are.same({ "new", "rt", clock + 3600 }, { saved.access_token, saved.refresh_token, saved.expires_at })
  end)

  it("clears the store only on invalid_grant", function()
    stored({ refresh_token = "rt", expires_at = 0 })
    oauth.http = fakehttp.new({ { match = "/token", response = { status = 400, body = '{"error":"invalid_grant"}' } } })
    local token, err = run(function()
      return session():token()
    end)
    assert.is_nil(token)
    assert.are.equal("revoked", err.kind)
    assert.is_nil(store.items.google)
  end)

  it("leaves the store alone when offline, timed out, or refused for another reason", function()
    for _, case in ipairs({
      { response = { err = { kind = "unreachable", message = "dns" } }, kind = "unreachable" },
      { response = { err = { kind = "timeout", message = "slow" } }, kind = "timeout" },
      { response = { status = 500, body = "" }, kind = "refresh_failed" },
      { response = { status = 400, body = '{"error":"invalid_client"}' }, kind = "refresh_failed" },
    }) do
      stored({ refresh_token = "rt", expires_at = 0 })
      oauth.http = fakehttp.new({ { match = "/token", response = case.response } })
      local token, err = run(function()
        return session():token()
      end)
      assert.is_nil(token)
      assert.are.equal(case.kind, err.kind)
      assert.are.equal("rt", vim.json.decode(store.items.google).refresh_token)
    end
  end)

  it("turns a refresh that raises into refresh_failed and recovers on the next call", function()
    stored({ refresh_token = "rt", expires_at = 0 })
    local original = oauth.refresh
    oauth.refresh = function()
      error("boom")
    end
    local s = session()
    local token, err = run(function()
      return s:token()
    end)
    oauth.refresh = original
    assert.is_nil(token)
    assert.are.equal("refresh_failed", err.kind)
    assert.truthy(err.message:find("boom", 1, true))
    assert.are.equal("rt", vim.json.decode(store.items.google).refresh_token)
    refresh_ok()
    assert.are.equal(
      "new",
      run(function()
        return s:token()
      end)
    )
  end)

  it("refreshes again after invalidate", function()
    stored({ access_token = "at", refresh_token = "rt", expires_at = clock + 3600 })
    refresh_ok()
    local s = session()
    local tokens = run(function()
      local first = s:token()
      s:invalidate()
      return { first, s:token() }
    end)
    assert.are.same({ "at", "new" }, tokens)
    assert.are.equal(1, #oauth.http.calls)
  end)

  it("saves, reports presence, and clears", function()
    local s = session()
    local present = run(function()
      s:save({ access_token = "at", refresh_token = "rt", expires_at = clock + 10 })
      return s:present()
    end)
    assert.is_true(present)
    assert.are.equal("rt", vim.json.decode(store.items.google).refresh_token)
    present = run(function()
      s:clear()
      return s:present()
    end)
    assert.is_false(present)
    assert.is_nil(store.items.google)
  end)
end)
