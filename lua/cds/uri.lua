---@tag cds.uri
---@toc_entry Relative document URLs
---@text
--- Resolve relative web links against a base URL, preserving queries for empty and fragment-only references.

local M = {}

--- Collapses `.` and `..` segments of an absolute path (RFC 3986 5.2.4). A
--- `..` at the root stays at the root.
---@param path string begins with "/"
---@return string
local function dedot(path)
  local out = {}
  local segments = {}
  for segment in (path .. "/"):gmatch("([^/]*)/") do
    segments[#segments + 1] = segment
  end
  table.remove(segments, 1) -- the empty piece before the leading slash
  local last = #segments
  for i, segment in ipairs(segments) do
    if segment == ".." then
      if #out > 0 then
        out[#out] = nil
      end
      if i == last then
        out[#out + 1] = ""
      end
    elseif segment == "." then
      if i == last then
        out[#out + 1] = ""
      end
    else
      out[#out + 1] = segment
    end
  end
  return "/" .. table.concat(out, "/")
end

--- Resolves `href` against `base` (RFC 3986 section 5.2): an absolute href
--- stands, `//host/x` takes the base's scheme, `/x` takes its scheme and
--- host, anything else joins to the base path's directory; dot segments are
--- removed and the href's own query and fragment are kept.
---@param base string an absolute http(s) URL
---@param href string
---@return string
function M.resolve(base, href)
  if href:match("^%a[%w+.-]*:") then
    return href
  end
  local scheme, authority, rest = base:match("^(%a[%w+.-]*)://([^/?#]*)(.*)$")
  if not scheme then
    return href
  end
  if href:sub(1, 2) == "//" then
    return scheme .. ":" .. href
  end
  local base_path = rest:match("^([^?#]*)")
  if base_path == "" then
    base_path = "/"
  end
  local path, tail
  if href:sub(1, 1) == "/" then
    path, tail = href:match("^([^?#]*)(.*)$")
  elseif href == "" or href:sub(1, 1) == "#" then
    path, tail = base_path, (rest:match("^[^?#]*(%?[^#]*)") or "") .. href
  elseif href:sub(1, 1) == "?" then
    path, tail = base_path, href
  else
    local target
    target, tail = href:match("^([^?#]*)(.*)$")
    path = base_path:match("^(.*/)") .. target
  end
  return scheme .. "://" .. authority .. dedot(path) .. tail
end

return M
