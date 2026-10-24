local async = require("cds.async")
local fakehttp = require("fakehttp")
local oauth = require("cds.oauth")

local client = {
  id = "cid",
  secret = "csecret",
  auth_url = "https://auth.test/authorize",
  token_url = "https://auth.test/token",
  revoke_url = "https://auth.test/revoke",
  scopes = { "calendar.events", "other" },
}

local token_json = '{"access_token":"at","refresh_token":"rt","expires_in":3600,"scope":"calendar.events"}'

--- Connects to the login's loopback port and sends the browser's redirect.
local function redirect(url, query)
  local port = tonumber(url:match("127%.0%.0%.1%%3A(%d+)"))
  local sock = vim.uv.new_tcp()
  local got = {}
  sock:connect("127.0.0.1", port, function()
    sock:write(("GET /?%s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"):format(query))
    sock:read_start(function(_, chunk)
      if chunk then
        table.insert(got, chunk)
      else
        sock:close()
      end
    end)
  end)
  return got
end

describe("cds.oauth", function()
  local original_http
  before_each(function()
    original_http = oauth.http
  end)
  after_each(function()
    oauth.http = original_http
  end)

  it("form-encodes with sorted names and percent escapes", function()
    assert.are.equal("a=1%202&b=x%3Ay%2Fz%26w", oauth.form({ b = "x:y/z&w", a = "1 2" }))
    assert.are.same({ code = "4/abc", state = "s" }, oauth.parse_query("state=s&code=4%2Fabc"))
  end)

  it("derives an S256 challenge from the verifier", function()
    local verifier, challenge = oauth.pkce()
    assert.are.equal(43, #verifier)
    assert.truthy(challenge:match("^[%w%-_]+$"))
    assert.are_not.equal(verifier, challenge)
  end)

  describe("login", function()
    local function login(opts, script)
      oauth.http = fakehttp.new(script or { { match = "/token", response = { body = token_json } } })
      return async.run(function()
        return oauth.login(client, opts)
      end)
    end

    it("opens the authorization URL, answers the redirect and exchanges the code", function()
      local url
      local task = login({
        open = function(u)
          url = u
        end,
      })
      vim.wait(500, function()
        return url ~= nil
      end)
      local params = oauth.parse_query(url:match("%?(.*)$"))
      assert.are.same({ "cid", "code", "calendar.events other", "offline", "consent", "S256" }, {
        params.client_id,
        params.response_type,
        params.scope,
        params.access_type,
        params.prompt,
        params.code_challenge_method,
      })
      assert.truthy(params.redirect_uri:match("^http://127%.0%.0%.1:%d+/$"))
      local got = redirect(url, "state=" .. params.state .. "&code=4%2Fxyz")
      local set, err = task:wait(2000)
      assert.is_nil(err)
      assert.are.same({ "at", "rt", "calendar.events" }, { set.access_token, set.refresh_token, set.scope })
      assert.truthy(set.expires_at > os.time() + 3500)
      vim.wait(500, function()
        return #got > 0
      end)
      assert.truthy(table.concat(got):match("You can close this tab"))
      local exchange = oauth.parse_query(oauth.http.calls[1].body)
      assert.are.same({ "authorization_code", "4/xyz", params.redirect_uri, "cid", "csecret" }, {
        exchange.grant_type,
        exchange.code,
        exchange.redirect_uri,
        exchange.client_id,
        exchange.client_secret,
      })
      assert.are.equal(43, #exchange.code_verifier)
    end)

    it("runs the code exchange on the main loop, outside a fast event context", function()
      local url, fast
      local task = login({
        open = function(u)
          url = u
        end,
      }, {
        {
          match = "/token",
          response = function()
            fast = vim.in_fast_event()
            return { body = token_json }
          end,
        },
      })
      vim.wait(500, function()
        return url ~= nil
      end)
      redirect(url, "state=" .. oauth.parse_query(url:match("%?(.*)$")).state .. "&code=c")
      task:wait(2000)
      assert.is_false(fast)
    end)

    it("rejects a redirect whose state does not match", function()
      local url
      local task = login({
        open = function(u)
          url = u
        end,
      })
      vim.wait(500, function()
        return url ~= nil
      end)
      redirect(url, "state=forged&code=4%2Fxyz")
      local set, err = task:wait(2000)
      assert.is_nil(set)
      assert.are.equal("state", err.kind)
      assert.are.same({}, oauth.http.calls)
    end)

    it("reports a denied consent", function()
      local url
      local task = login({
        open = function(u)
          url = u
        end,
      })
      vim.wait(500, function()
        return url ~= nil
      end)
      redirect(url, "error=access_denied")
      local set, err = task:wait(2000)
      assert.is_nil(set)
      assert.are.same({ "denied", "access_denied" }, { err.kind, err.message })
    end)

    it("times out when the browser never comes back", function()
      local task = login({ open = function() end, timeout = 50 })
      local set, err = task:wait(2000)
      assert.is_nil(set)
      assert.are.equal("timeout", err.kind)
    end)

    it("reports a raise while waiting for the redirect instead of dying", function()
      local original = oauth.parse_query
      oauth.parse_query = function()
        error("parse boom")
      end
      local url
      local task = login({
        open = function(u)
          url = u
        end,
      })
      vim.wait(500, function()
        return url ~= nil
      end)
      redirect(url, "state=x&code=c")
      local ok, set, err = pcall(task.wait, task, 2000)
      oauth.parse_query = original
      assert.is_true(ok)
      assert.is_nil(set)
      assert.are.equal("internal", err.kind)
      assert.truthy(err.message:find("parse boom", 1, true))
    end)

    it("passes a token endpoint failure through", function()
      local url
      local task = login({
        open = function(u)
          url = u
        end,
      }, { { match = "/token", response = { status = 400, body = '{"error":"invalid_client"}' } } })
      vim.wait(500, function()
        return url ~= nil
      end)
      redirect(url, "state=" .. oauth.parse_query(url:match("%?(.*)$")).state .. "&code=c")
      local set, err = task:wait(2000)
      assert.is_nil(set)
      assert.are.same({ "token_endpoint", "invalid_client" }, { err.kind, err.message })
    end)
  end)

  it("classifies token endpoint responses", function()
    local set, err = oauth.token_response(nil, { kind = "timeout", message = "t" }, 0)
    assert.is_nil(set)
    assert.are.equal("timeout", err.kind)
    set, err =
      oauth.token_response({ status = 400, body = '{"error":"invalid_grant","error_description":"gone"}' }, nil, 0)
    assert.is_nil(set)
    assert.are.same({ "invalid_grant", "gone" }, { err.kind, err.message })
    set, err = oauth.token_response({ status = 500, body = "<html>" }, nil, 0)
    assert.is_nil(set)
    assert.are.same({ "token_endpoint", "HTTP 500" }, { err.kind, err.message })
    set = oauth.token_response({ status = 200, body = '{"access_token":"a","expires_in":10}' }, nil, 100)
    assert.are.same({ access_token = "a", expires_at = 110 }, set)
  end)

  it("revokes best effort", function()
    oauth.http = fakehttp.new({ { match = "/revoke", response = { status = 200 } } })
    assert.is_true(async
      .run(function()
        return oauth.revoke(client, "rt")
      end)
      :wait(500))
    assert.are.equal("token=rt", oauth.http.calls[1].body)
    oauth.http = fakehttp.new({ { match = "/revoke", response = { err = { kind = "unreachable", message = "off" } } } })
    local ok, err = async
      .run(function()
        return oauth.revoke(client, "rt")
      end)
      :wait(500)
    assert.is_false(ok)
    assert.are.equal("off", err)
  end)
end)
