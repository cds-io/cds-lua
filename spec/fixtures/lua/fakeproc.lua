-- A replacement for cds.proc.runner: matches argv against scripted patterns,
-- returns recorded output, and remembers every call with its stdin so a spec
-- can assert what reached argv and what stayed on stdin.
local proc = require("cds.proc")

local M = {}

--- Install the fake. `scripts` is a list of { match, result } where `match`
--- is a function(argv, opts) → boolean, or a string found in the joined argv,
--- and `result` is { code, stdout, stderr } or a function(argv, opts) → that.
---@param scripts table[]
function M.install(scripts)
  M.calls = {}
  M.original = M.original or proc.runner
  proc.runner = function(argv, opts)
    table.insert(M.calls, { argv = vim.deepcopy(argv), stdin = opts.stdin })
    local joined = table.concat(argv, " ")
    for _, s in ipairs(scripts) do
      local hit
      if type(s.match) == "function" then
        hit = s.match(argv, opts)
      else
        hit = joined:find(s.match, 1, true)
      end
      if hit then
        local r = type(s.result) == "function" and s.result(argv, opts) or s.result
        return { code = r.code or 0, signal = r.signal or 0, stdout = r.stdout or "", stderr = r.stderr or "" }
      end
    end
    error(("fakeproc: no script matches %s"):format(joined))
  end
end

function M.uninstall()
  if M.original then
    proc.runner = M.original
  end
end

--- Every argv element across all calls, joined, for "never on argv" assertions.
function M.all_argv()
  local parts = {}
  for _, c in ipairs(M.calls) do
    vim.list_extend(parts, c.argv)
  end
  return table.concat(parts, "\n")
end

return M
