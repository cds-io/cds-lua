local async = require("cds.async")
local fakeproc = require("fakeproc")
local http = require("cds.http")

describe("cds.http", function()
  after_each(fakeproc.uninstall)

  local function request(req)
    return async
      .run(function()
        return http.request(req)
      end)
      :wait(1000)
  end

  local function ok_response(status, body, extra_headers)
    return {
      stdout = ("HTTP/2 %d\r\ncontent-type: application/json\r\n%s\r\n%s\n--cds-http-status:%d"):format(
        status,
        extra_headers or "",
        body,
        status
      ),
    }
  end

  it("names the statuses the family branches on, and knows a transient one", function()
    local status = require("cds.http").status
    assert.are.equal(200, status.OK)
    assert.are.equal(304, status.NOT_MODIFIED)
    assert.are.equal(401, status.UNAUTHORIZED)
    assert.are.equal(404, status.NOT_FOUND)
    assert.are.equal(409, status.CONFLICT)
    assert.is_true(status.transient(500))
    assert.is_true(status.transient(503))
    assert.is_false(status.transient(499))
    assert.is_false(status.transient(600))
  end)
  it("writes every option to the config on stdin and keeps argv fixed", function()
    fakeproc.install({ { match = "curl", result = ok_response(200, "{}") } })
    request({
      method = "POST",
      url = "https://api.test/x",
      headers = { Authorization = "Bearer sekrit" },
      body = '{"a":"b"}',
    })
    assert.are.same({ "curl", "--config", "-" }, fakeproc.calls[1].argv)
    local cfg = fakeproc.calls[1].stdin
    assert.truthy(cfg:find('url = "https://api.test/x"', 1, true))
    assert.truthy(cfg:find('request = "POST"', 1, true))
    assert.truthy(cfg:find('header = "Authorization: Bearer sekrit"', 1, true))
    assert.truthy(cfg:find('data-raw = "{\\"a\\":\\"b\\"}"', 1, true))
    assert.falsy(fakeproc.all_argv():find("sekrit", 1, true))
  end)

  it("asks curl to follow a redirect, a few at most, so a moved document is still the document", function()
    fakeproc.install({ { match = "curl", result = ok_response(200, "{}") } })
    request({ method = "GET", url = "https://api.test/moved" })
    local cfg = fakeproc.calls[1].stdin
    assert.truthy(cfg:find("\nlocation\n", 1, true))
    assert.truthy(cfg:find("max-redirs = 5", 1, true))
  end)
  it("quotes backslashes, quotes and newlines for curl's config parser", function()
    assert.are.equal('"a\\\\b \\"c\\" d\\ne"', http.quote('a\\b "c" d\ne'))
  end)

  it("returns the status, lower-cased headers and body of any response", function()
    fakeproc.install({ { match = "curl", result = ok_response(409, '{"error":"dup"}', "X-Test: yes\r\n") } })
    local res, err = request({ method = "GET", url = "https://api.test/x" })
    assert.is_nil(err)
    assert.are.same({ status = 409, body = '{"error":"dup"}', xtest = "yes" }, {
      status = res.status,
      body = res.body,
      xtest = res.headers["x-test"],
    })
  end)

  it("keeps the last header block when curl dumps several", function()
    local out = "HTTP/1.1 100 Continue\r\n\r\nHTTP/2 200\r\na: 1\r\n\r\nbody\n--cds-http-status:200"
    local res = http.parse(out)
    assert.are.same({ 200, "1", "body" }, { res.status, res.headers.a, res.body })
  end)

  it("classifies curl exit codes", function()
    local cases = {
      [6] = "unreachable",
      [7] = "unreachable",
      [28] = "timeout",
      [35] = "tls",
      [60] = "tls",
      [52] = "interrupted",
      [55] = "interrupted",
      [56] = "interrupted",
      [22] = "curl",
    }
    for code, kind in pairs(cases) do
      fakeproc.install({ { match = "curl", result = { code = code, stderr = "curl: (" .. code .. ") boom" } } })
      local res, err = request({ method = "GET", url = "https://api.test/x" })
      assert.is_nil(res)
      assert.are.equal(kind, err.kind)
      assert.are.equal(("curl exit %d: curl: (%d) boom"):format(code, code), err.message)
    end
  end)

  it("reports a process killed by the proc timeout as a timeout", function()
    fakeproc.install({ { match = "curl", result = { code = 124, signal = 15 } } })
    local res, err = request({ method = "GET", url = "https://api.test/x" })
    assert.is_nil(res)
    assert.are.equal("timeout", err.kind)
  end)

  it("sends the body as data-raw, so a leading @ is data and not a file name", function()
    fakeproc.install({ { match = "curl", result = ok_response(200, "{}") } })
    request({ method = "POST", url = "https://api.test/x", body = "@/etc/hosts" })
    assert.truthy(fakeproc.calls[1].stdin:find('data-raw = "@/etc/hosts"', 1, true))
  end)

  it("reports each request to the trace hook, without headers, body or query", function()
    local seen = {}
    http.trace = function(rec)
      table.insert(seen, rec)
    end
    fakeproc.install({ { match = "curl", result = ok_response(200, "{}") } })
    request({
      method = "POST",
      url = "https://api.test/x?token=sekrit-q",
      headers = { Authorization = "Bearer sekrit-h" },
      body = "sekrit-b",
    })
    fakeproc.install({ { match = "curl", result = { code = 28, stderr = "slow" } } })
    request({ method = "GET", url = "https://api.test/y" })
    http.trace = nil
    assert.are.same({ method = "POST", url = "https://api.test/x", status = 200 }, {
      method = seen[1].method,
      url = seen[1].url,
      status = seen[1].status,
    })
    assert.are.same({ "GET", "https://api.test/y", "timeout" }, { seen[2].method, seen[2].url, seen[2].kind })
    assert.is_number(seen[1].ms)
    assert.falsy(vim.inspect(seen):find("sekrit", 1, true))
  end)

  it("reports a missing curl as a spawn error", function()
    local proc = require("cds.proc")
    local original = proc.runner
    proc.runner = function()
      error("ENOENT: no such file or directory (cmd): 'curl'")
    end
    local res, err = request({ method = "GET", url = "https://api.test/x" })
    proc.runner = original
    assert.is_nil(res)
    assert.are.equal("spawn", err.kind)
    assert.truthy(err.message:match("^curl: ENOENT"))
  end)
end)
