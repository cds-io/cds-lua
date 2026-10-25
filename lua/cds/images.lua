---@tag cds.images
---@toc_entry Displaying inline images
---@text
--- Displays images below buffer lines through an optional image plugin.
--- Call place with a buffer, window, row, image URL or file path, and maximum
--- height. It returns a placement that you can remove with clear; clear_all
--- removes all placements in a buffer.
---
--- The supported backend is image.nvim. It must be installed and enabled;
--- this module handles its rendering calls and asynchronous image loading.
--- Use available() to check whether images can be displayed. Without an
--- available backend, place returns nil and draws nothing, so callers should
--- keep captions or alternative text readable without images.
---
--- Display a placeholder image ~
--- Run this in Neovim with image.nvim installed, configured, and enabled in
--- a terminal it supports. The placeholder service returns an image directly;
--- no JSON API request is needed. Its URL syntax is documented at
--- https://tools.placeholder.com/images (part of the Placeholder tools).
--- The remote image requires network access; a local file path works too.
--- >lua
---   local images = require("cds.images")
---   local buf = vim.api.nvim_create_buf(false, true)
---   local win = vim.api.nvim_get_current_win()
---   vim.api.nvim_win_set_buf(win, buf)
---   vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
---     "Example: a 600 by 400 placeholder image",
---     "Close this buffer to remove its image.",
---   })
---
---   -- Register cleanup before starting the asynchronous download.
---   vim.api.nvim_create_autocmd("BufWipeout", {
---     buffer = buf,
---     once = true,
---     callback = function() images.clear_all(buf) end,
---   })
---   if images.available() then
---     local placement, err = images.place({
---       buf = buf,
---       win = win,
---       row = 1,
---       url = "https://via.placeholder.com/600x400.png?text=Example+image",
---       max_height = 10,
---     })
---     if not placement and err then
---       vim.notify(tostring(err), vim.log.levels.WARN)
---     end
---   end
--- <
--- The caption remains readable without a backend. row is 1-based and places
--- the image below that buffer line; max_height is measured in terminal rows.
--- For a remote URL, a placement means loading has started, not that the image
--- is already visible. To remove it earlier, pass it to images.clear().
--- Clearing before the download finishes also prevents rendering on arrival.
---@class cds.images
local M = {}

---@class cds.images.Spec
---@field buf integer
---@field win integer
---@field row integer       -- 1-based; the image goes below this line
---@field url string        -- an http(s) URL or a file path
---@field max_height integer -- rows

---@class cds.images.Placement
---@field buf integer
---@field backend table
---@field image any|nil     -- the backend's object once it exists
---@field cleared boolean|nil

---@class cds.images.Backend
---@field name string
---@field available fun(): boolean
---@field place fun(spec: cds.images.Spec, placement: cds.images.Placement): cds.images.Placement|nil, string|nil
---@field clear fun(placement: cds.images.Placement)

--- image.nvim: from_url and from_file bind an image to a buffer and a
--- window, inline below a row, padding the buffer with virtual lines;
--- from_url is asynchronous, so the placement is filled in when the
--- image arrives, and a placement cleared before then clears the image
--- on arrival.
local image_nvim = {
  name = "image.nvim",
  available = function()
    local ok, image = pcall(require, "image")
    return ok and type(image.is_enabled) == "function" and image.is_enabled() == true
  end,
  place = function(spec, placement)
    local image = require("image")
    local opts = {
      window = spec.win,
      buffer = spec.buf,
      inline = true,
      with_virtual_padding = true,
      x = 0,
      y = spec.row - 1, -- the extmark row, 0-based
      -- `height` would be the exact height, scaling a small diagram up;
      -- the per-image percentage of the window is the cap it offers
      max_height_window_percentage = spec.max_height / vim.api.nvim_win_get_height(spec.win) * 100,
    }
    local function show(img)
      if not img then
        return
      end
      if placement.cleared then
        img:clear()
        return
      end
      placement.image = img
      img:render()
    end
    if spec.url:match("^https?://") then
      image.from_url(spec.url, opts, show)
    else
      show(image.from_file(spec.url, opts))
    end
    return placement
  end,
  clear = function(placement)
    if placement.image then
      placement.image:clear()
      placement.image = nil
    end
    placement.cleared = true
  end,
}

-- The backends, first available wins.
M._backends = { image_nvim }

-- A backend forced by a spec: a table to use it, false for none, nil for
-- the usual choice.
local forced = nil

-- The placements made, by buffer.
---@type table<integer, cds.images.Placement[]>
local placements = {}

--- For specs: uses this backend (a table), none (false), or the usual (nil),
--- forgetting the placements made so far, since they were another backend's.
---@param backend table|false|nil
function M._use(backend)
  forced = backend
  placements = {}
end

---@return cds.images.Backend|nil
local function backend()
  if forced == false then
    return nil
  elseif forced then
    return forced
  end
  for _, b in ipairs(M._backends) do
    if b.available() then
      return b
    end
  end
  return nil
end

--- Whether a backend is loaded and can draw here.
---@return boolean
function M.available()
  return backend() ~= nil
end

--- Draws the image at `spec.url` inline below `spec.row`; the placement,
--- or nil and the reason when the backend refuses; nil without a backend.
---@param spec cds.images.Spec
---@return cds.images.Placement|nil
---@return string|nil err
function M.place(spec)
  local b = backend()
  if not b then
    return nil
  end
  local placement = { buf = spec.buf, backend = b }
  local made, err = b.place(spec, placement)
  if not made then
    return nil, err
  end
  -- whatever table the backend answers is the placement the adapter clears
  made.backend = b
  made.buf = made.buf or spec.buf
  placements[spec.buf] = placements[spec.buf] or {}
  table.insert(placements[spec.buf], made)
  return made
end

--- Removes one placement, once.
---@param placement cds.images.Placement|nil
function M.clear(placement)
  if placement and placement.backend and not placement.cleared then
    placement.backend.clear(placement)
    placement.cleared = true
  end
end

--- Removes every placement made in the buffer.
---@param buf integer
function M.clear_all(buf)
  for _, p in ipairs(placements[buf] or {}) do
    M.clear(p)
  end
  placements[buf] = nil
end

return require("cds.module").wrap("images", M)
