---@tag cds.document_view
---@toc_entry Document display lifecycle
---@text
--- new(deps) supplies show(model, opts) and window_of(buf). Inject current(model), render(markdown, width), draw(buf,
--- rendered), attach(buf), attach_window(win), image_wait(), group and filetype, and style_delay in milliseconds (30
--- unless given). show draws the Markdown itself at once and the styled rendering after the delay, so a reader sees a
--- long document while vellum works on it; a document hidden when the delay ends is styled when a window shows it.
--- Every redraw keeps each window's cursor on the same source row, mapped through the rendered blocks, and the views
--- handed to show (winsaveview tables by window) are applied once the styled draw is in, and a cds.progress report
--- handed to show is told of the styling phase and finished once the final draw is in. The view retries pending
--- images and watches resize and colorscheme events while the model remains current. The model carries buf and
--- markdown; rendering writes doc, width and draws. Hidden image retries resume on entry without restarting an
--- exhausted budget.

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
---@field style_delay? integer -- milliseconds between the Markdown draw and the styled one; 30 unless given
---@field styled_max_lines? integer -- a page with more Markdown lines stays plain, under the document's
--- filetype; 20000 unless given

---@class cds.DocumentShowOptions
---@field views? table<integer, table> -- winsaveview tables by window, applied after the styled draw
---@field report? cds.ProgressReport -- told of the styling phase and finished once the final draw is in

---@class cds.DocumentView
---@field show fun(model: cds.DocumentModel, opts?: cds.DocumentShowOptions)
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
  ---@field package plain boolean -- the Markdown is drawn and the styled draw is still to come
  ---@field package styling boolean -- a styled draw is on the next tick
  ---@field package views? table<integer, table> -- the views handed to show, until applied
  ---@field package report? cds.ProgressReport -- the report handed to show, until finished

  ---@type table<integer, cds.DocumentDisplayState>
  local sessions = {}
  ---@type fun(model: cds.DocumentModel, state: cds.DocumentDisplayState, event: string)
  local refresh

  -- The first wait for vellum's images, in milliseconds, doubled for each
  -- try after it; and the tries.
  local IMAGE_TRIES = 6
  local STYLE_DELAY = 30
  local STYLED_MAX_LINES = 20000

  --- The windows showing `buf` with their views and the source row each
  --- cursor is on in the layout drawn now, so a redraw can put it back.
  ---@param model cds.DocumentModel
  ---@return { win: integer, view: table, row: integer, top: integer }[]
  local function held_views(model)
    local held = {}
    for _, win in ipairs(vim.fn.win_findbuf(model.buf)) do
      local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
      local layout = model.doc or { styled = false }
      held[#held + 1] = {
        win = win,
        view = view,
        row = document.source_row(layout, view.lnum),
        top = document.source_row(layout, view.topline),
      }
    end
    return held
  end

  --- The held views put back in the layout drawn now, each cursor on the
  --- rendered row of its source row; then the views handed to show, once the
  --- draw is the final one.
  ---@param model cds.DocumentModel
  ---@param state cds.DocumentDisplayState
  ---@param held { win: integer, view: table, row: integer, top: integer }[]
  ---@param final boolean
  local function restore_views(model, state, held, final)
    for _, h in ipairs(held) do
      if vim.api.nvim_win_is_valid(h.win) and vim.api.nvim_win_get_buf(h.win) == model.buf then
        h.view.lnum = document.rendered_row(model.doc, h.row)
        h.view.topline = document.rendered_row(model.doc, h.top)
        vim.api.nvim_win_call(h.win, function()
          vim.fn.winrestview(h.view)
        end)
      end
    end
    if final and state.views then
      for win, view in pairs(state.views) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == model.buf then
          vim.api.nvim_win_call(win, function()
            vim.fn.winrestview(view)
          end)
        end
      end
      state.views = nil
    end
  end

  --- The Markdown itself into the buffer, as the first thing a reader sees
  --- of a document and all of it on a machine without vellum: filetype
  --- markdown, so treesitter colours it, with the caller's keys attached.
  --- A page over styled_max_lines is final as drawn, under the document's
  --- own filetype: treesitter over tens of thousands of lines and vellum's
  --- render of them cost seconds a reader would wait frozen for, on a page
  --- whose styling adds little.
  ---@param model cds.DocumentModel
  ---@param state cds.DocumentDisplayState
  ---@param final boolean   -- no styled draw will follow
  local function draw_plain(model, state, final)
    local buf = model.buf
    local markdown = model.document and model.document.markdown or assert(model.markdown)
    model.width = nil
    model.doc = document.rendered(model.document or document.new(markdown), nil, nil, nil, nil)
    deps.draw(buf, model.doc)
    local filetype = final and deps.filetype or "markdown"
    if vim.bo[buf].filetype ~= filetype then
      vim.bo[buf].filetype = filetype
    end
    deps.attach(buf)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      deps.attach_window(win)
    end
    model.draws = (model.draws or 0) + 1
    state.plain = not final
    if state.report then
      state.report:mark("Markdown drawn")
      if final then
        state.report:mark(
          ("styling skipped: %d lines, over %d"):format(#markdown, deps.styled_max_lines or STYLED_MAX_LINES)
        )
        state.report:finish()
        state.report = nil
      end
    end
  end

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
    local held = held_views(model)
    local waiting
    for _ = 1, 2 do
      local width = text_width(window_of(buf))
      local lines, marks, blocks
      lines, marks, waiting, blocks = deps.render(markdown, width - 2)
      model.width = lines and width or nil
      model.doc = document.rendered(model.document or document.new(markdown), lines, marks, waiting, blocks)
      deps.draw(buf, model.doc)
      local filetype = lines and deps.filetype or "markdown"
      local changed = vim.bo[buf].filetype ~= filetype
      if changed then
        vim.bo[buf].filetype = filetype
      end
      -- a filetype change runs the old filetype's undo_ftplugin, which can
      -- unmap a key the caller set under the same name (markdown's gO), so
      -- the caller's keys go back on after it
      if changed or not lines then
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
    if state.plain and state.report then
      state.report:mark(model.doc.styled and "styled drawn" or "Markdown kept")
      state.report:finish()
      state.report = nil
    end
    state.plain = false
    restore_views(model, state, held, true)
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
    if state.plain then
      -- the styled draw still to come: on the next tick, if a window shows
      -- the document then. The tick matters: a :tabnew shows the old buffer
      -- in its new window for the instant its TabEnter fires.
      if state.visible and not state.styling then
        state.styling = true
        if state.report then
          state.report:begin("styling")
        end
        vim.schedule(function()
          state.styling = false
          if
            sessions[model.buf] == state
            and state.plain
            and deps.current(model)
            and vim.fn.bufwinid(model.buf) ~= -1
          then
            draw_item(model, state, 0)
          end
        end)
      end
      return
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

  --- Shows the model: the Markdown now, the styled draw after the delay
  --- while a window still shows the document (a hidden one is styled when
  --- shown), the views in `opts` applied after the styled draw.
  ---@param model cds.DocumentModel
  ---@param opts? cds.DocumentShowOptions
  function M.show(model, opts)
    local state = {
      dirty = false,
      visible = false,
      pending = false,
      resume = false,
      scheduled = false,
      attempt = 0,
      generation = 0,
      plain = false,
      styling = false,
      views = opts and opts.views or nil,
      report = opts and opts.report or nil,
    }
    local buf = model.buf
    sessions[buf] = state
    local markdown = model.document and model.document.markdown or assert(model.markdown)
    local too_long = #markdown > (deps.styled_max_lines or STYLED_MAX_LINES)
    draw_plain(model, state, too_long)
    watch(model, state)
    if too_long then
      return
    end
    vim.defer_fn(function()
      if sessions[buf] == state and state.plain and deps.current(model) then
        refresh(model, state, "style")
      end
    end, deps.style_delay or STYLE_DELAY)
  end
  M.window_of = window_of
  return M
end
return View
