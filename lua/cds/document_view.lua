---@tag cds.document_view
---@toc_entry Document display lifecycle
---@text
--- new(deps) supplies show(model) and window_of(buf). Inject current(model), render(markdown, width), draw(buf,
--- rendered), attach(buf), attach_window(win), image_wait(), group and filetype. The view retries pending images
--- and watches resize and colorscheme events while the model remains current. The model carries buf and markdown;
--- rendering writes doc, width and draws. Hidden image retries resume on entry without restarting an exhausted budget.

---@class cds.DocumentModel
---@field buf integer
---@field document? cds.Document
---@field markdown? string[]
---@field doc? cds.RenderedDocument
---@field width? integer
---@field draws? integer

local document = require("cds.document")

---@class cds.DocumentViewDependencies
---@field current fun(model: cds.DocumentModel): boolean
---@field render fun(markdown: string[], width: integer): string[]?, cds.DocumentMark[]?, boolean?, integer[][]?
---@field draw fun(buf: integer, rendered: cds.RenderedDocument)
---@field attach fun(buf: integer)
---@field attach_window fun(win: integer)
---@field image_wait fun(): number
---@field group string -- autocmd namespace owned by this presenter
---@field filetype string -- styled rendering's filetype; Markdown is the fallback

---@class cds.DocumentView
---@field show fun(model: cds.DocumentModel)
---@field window_of fun(buf: integer): integer

local View = {}

--- Rendering lifecycle for a model carrying buf, markdown, doc and width.
--- The caller supplies buffer policy and a model identity guard. Image retries
--- and resize callbacks never draw a model that the caller considers stale.
---@param deps cds.DocumentViewDependencies
---@return cds.DocumentView
function View.new(deps)
  local M = {}
  --- The window showing `buf`; the current one when none does yet, as during
  --- the read of an :edit, which runs in the window the buffer is going into.
  ---@param buf integer
  ---@return integer
  local function window_of(buf)
    local win = vim.fn.bufwinid(buf)
    return win ~= -1 and win or vim.api.nvim_get_current_win()
  end

  --- The columns of `win` that hold text: its width less the gutter.
  ---@param win integer
  ---@return integer
  local function text_width(win)
    local info = vim.fn.getwininfo(win)[1]
    return info.width - info.textoff
  end

  -- One lifecycle per shown model. Replacing it invalidates its timers.
  ---@class cds.DocumentDisplayState
  ---@field package dirty boolean
  ---@field package visible boolean
  ---@field package pending boolean
  ---@field package resume boolean
  ---@field package scheduled boolean
  ---@field package attempt integer
  ---@field package generation integer

  ---@type table<integer, cds.DocumentDisplayState>
  local sessions = {}
  ---@type fun(model: cds.DocumentModel, state: cds.DocumentDisplayState, event: string)
  local refresh

  -- The first wait for vellum's images, in milliseconds, doubled for each
  -- try after it; and the tries.
  local IMAGE_TRIES = 6

  --- The model's Markdown (an item's article, or a followed page) into its
  --- buffer: vellum's lines and marks, wrapped to the window's text area less
  --- two, when vellum renders it; the Markdown itself otherwise, as filetype
  --- markdown so treesitter colours it. The caller attaches keys
  --- for its own filetype and for the Markdown fallback. A styled article
  --- or page turns the window's gutter off, which widens the text area, so
  --- the first draw into a window with a gutter is done again at the wider
  --- width.
  ---
  --- vellum answers a placeholder for a remote image until its browser has
  --- rendered it, and tells only its own preview when that is done, so an
  --- article that waited on one is drawn again after a wait, doubled each
  --- try, `IMAGE_TRIES` at most. A try draws only while the buffer still
  --- holds the model, shows in a window, and has been drawn by nothing since
  --- at the width it had: a redraw on a resize or a colorscheme starts tries
  --- of its own, and a wipe ends them.
  ---@param model cds.DocumentModel
  ---@param state cds.DocumentDisplayState
  ---@param try integer the tries before this draw
  local function draw_item(model, state, try)
    local buf = model.buf
    local markdown = model.document and model.document.markdown or assert(model.markdown)
    local waiting
    for _ = 1, 2 do
      local width = text_width(window_of(buf))
      local lines, marks, blocks
      lines, marks, waiting, blocks = deps.render(markdown, width - 2)
      model.width = lines and width or nil
      model.doc = document.rendered(model.document or document.new(markdown), lines, marks, waiting, blocks)
      deps.draw(buf, model.doc)
      local filetype = lines and deps.filetype or "markdown"
      if vim.bo[buf].filetype ~= filetype then
        vim.bo[buf].filetype = filetype
      end
      if not lines then
        deps.attach(buf)
      end
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        deps.attach_window(win)
      end
      if not lines or text_width(window_of(buf)) == width then
        break
      end
    end
    model.draws = (model.draws or 0) + 1
    state.dirty, state.resume, state.scheduled = false, false, false
    state.pending, state.attempt = model.doc.waiting, try
    state.visible = vim.fn.bufwinid(buf) ~= -1
    state.generation = state.generation + 1
    if not state.pending or try >= IMAGE_TRIES then
      return
    end
    local generation = state.generation
    state.scheduled = true
    vim.defer_fn(function()
      if sessions[buf] == state and state.generation == generation then
        refresh(model, state, "retry")
      end
    end, deps.image_wait() * 2 ^ try)
  end

  -- Resize, invalidation, entry and retry all use the same transition. A
  -- hidden retry becomes resumable work, without spending the retry budget.
  refresh = function(model, state, event)
    if sessions[model.buf] ~= state or not deps.current(model) then
      return
    end
    local win = vim.fn.bufwinid(model.buf)
    state.visible = win ~= -1
    if event == "ColorScheme" then
      state.dirty = true
    end
    if event == "retry" then
      state.scheduled, state.resume = false, state.pending
    end
    if not model.width or not state.visible then
      return
    end
    if state.dirty or text_width(win) ~= model.width then
      draw_item(model, state, 0)
    elseif state.pending and state.resume and not state.scheduled and state.attempt < IMAGE_TRIES then
      draw_item(model, state, state.attempt + 1)
    end
  end

  --- vellum's lines are wrapped to one width and coloured for one colorscheme,
  --- so they are drawn again when either changes, or on entry after a hidden
  --- change: one augroup per item buffer,
  --- gone with the buffer. The caller's ColorScheme autocmd must
  --- invalidate the renderer's theme before these redraws run.
  ---@param model cds.DocumentModel
  ---@param state cds.DocumentDisplayState
  local function watch(model, state)
    local buf = model.buf
    local group = vim.api.nvim_create_augroup(deps.group .. "_" .. buf, { clear = true })
    local function changed(event)
      refresh(model, state, event.event)
    end
    vim.api.nvim_create_autocmd({ "WinResized", "ColorScheme", "TabEnter" }, {
      group = group,
      callback = changed,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = buf,
      callback = changed,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        if sessions[buf] == state then
          sessions[buf] = nil
        end
        vim.api.nvim_del_augroup_by_id(group)
      end,
    })
  end

  function M.show(model)
    local state = {
      dirty = false,
      visible = false,
      pending = false,
      resume = false,
      scheduled = false,
      attempt = 0,
      generation = 0,
    }
    sessions[model.buf] = state
    draw_item(model, state, 0)
    watch(model, state)
  end
  M.window_of = window_of
  return M
end
return View
