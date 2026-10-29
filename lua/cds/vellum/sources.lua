-- Private source side of cds.vellum: the image sources vellum's loader
-- refuses, written as files it reads. vellum takes a local path or an
-- http(s) URL and answers a bare placeholder for any other scheme, so a
-- page that embeds its pictures as base64 data URIs (a scan's thumbnails,
-- a chart a site inlines) shows nothing for them. The decoded bytes go to a
-- file named by their hash, so one picture is one file however many
-- documents carry it, and a redraw costs a stat. Nothing prunes the
-- directory; a data URI is small by nature, and the files are few.

---@class cds.vellum.sources
local M = {}

-- vellum reads a PNG itself and sends any other format through its
-- browser, which goes by the file's extension.
local EXTENSION = {
  png = "png",
  jpeg = "jpg",
  jpg = "jpg",
  gif = "gif",
  webp = "webp",
  bmp = "bmp",
  avif = "avif",
  ["svg+xml"] = "svg",
}

--- The path under `dir` holding the bytes of a `data:image/<type>;base64,`
--- source, written when absent; nil for a type vellum cannot show or a
--- payload that is not base64.
---@param kind string   -- the media subtype: png, jpeg, svg+xml
---@param payload string
---@param dir string
---@return string|nil
local function file_of(kind, payload, dir)
  local extension = EXTENSION[kind:lower()]
  if not extension then
    return nil
  end
  local ok, bytes = pcall(vim.base64.decode, payload)
  if not ok then
    return nil
  end
  local path = ("%s/%s.%s"):format(dir, vim.fn.sha256(bytes), extension)
  if not vim.uv.fs_stat(path) then
    vim.fn.mkdir(dir, "p")
    local f = io.open(path, "wb")
    if not f then
      return nil
    end
    f:write(bytes)
    f:close()
  end
  return path
end

--- `markdown` with each image whose source is a base64 data URI pointing at
--- the file of its bytes under `dir`; every other line and source as it is,
--- and the same number of lines, so block anchors over the result place the
--- original's rows. The caller's table is left alone.
---@param markdown string[]
---@param dir string
---@return string[]
function M.materialise(markdown, dir)
  local out = {}
  for i, line in ipairs(markdown) do
    out[i] = line:find("](data:image/", 1, true)
        and line:gsub("%]%(data:image/([%w%+%-%.]+);base64,([%w%+/=]+)%)", function(kind, payload)
          local path = file_of(kind, payload, dir)
          return path and ("](" .. path .. ")") or nil
        end)
      or line
  end
  return out
end

return M
