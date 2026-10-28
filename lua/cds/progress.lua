---@tag cds.progress
---@toc_entry Progress reports
---@text
--- A report of work in phases, for a dashboard or a statusline to render:
--- the title, the elapsed time, the phases in order with the one running
--- marked, a bar on a phase that counts (pages of 32), each finished phase
--- with its seconds, and the error when one fails. `plan` names the phases
--- in order so the pending ones show from the start; a phase begun under a
--- name the plan lacks is appended. `lines(width)` renders it; `subscribe`
--- observes every change. No editor here: `now` is a millisecond clock,
--- the high-resolution one unless given (vim.uv.now is the loop's cached
--- time, the same reading for every phase begun inside one blocked turn).
---
--- >lua
---   local report = require("cds.progress").new({
---     title = "CRS reports by topic",
---     plan = { "reading source", "parsing metadata", "styling" },
---   })
---   report:begin("reading source", 32)
---   report:tick()          -- one page in
---   report:begin("parsing metadata")   -- ends reading source
---   report:finish()
--- <

---@class cds.progress
local M = {}
local lines = require("cds.progress.lines")

---@class cds.ProgressPhase
---@field name string
---@field status "pending"|"running"|"done"|"failed"
---@field started? integer   -- milliseconds, on the report's clock
---@field ended? integer
---@field count integer      -- units done, for a phase that counts
---@field of? integer        -- units in all, for a phase that counts
---@field err? string

---@class cds.progress.Options
---@field title string
---@field plan? string[]          -- the phase names, in order
---@field now? fun(): integer     -- milliseconds; the high-resolution clock unless given

---@class cds.ProgressEvent
---@field at integer          -- milliseconds after the report began
---@field kind "mark"|"block"
---@field name string         -- a mark's name; for a block, the phase running
---@field duration? integer   -- a block's milliseconds

---@class cds.ProgressReport
---@field title string
---@field phases cds.ProgressPhase[]
---@field events cds.ProgressEvent[]
---@field now fun(): integer
---@field started integer   -- milliseconds, on the report's clock; the renderer reads it
---@field package ended? integer
---@field mode "running"|"done"|"failed"   -- the renderer reads it
---@field package observers table<integer, fun(report: cds.ProgressReport)>
---@field package next_observer integer
local Report = {}
Report.__index = Report

--- Milliseconds from the high-resolution clock, read fresh on every call.
---@return integer
local function hr_now()
  return math.floor(vim.uv.hrtime() / 1e6)
end

---@param opts cds.progress.Options
---@return cds.ProgressReport
function M.new(opts)
  local now = opts.now or hr_now
  local report = setmetatable({
    title = opts.title,
    phases = {},
    events = {},
    now = now,
    started = now(),
    ended = nil,
    mode = "running",
    observers = {},
    next_observer = 0,
  }, Report)
  for _, name in ipairs(opts.plan or {}) do
    report.phases[#report.phases + 1] = { name = name, status = "pending", count = 0 }
  end
  return report
end

---@param self cds.ProgressReport
local function changed(self)
  for _, observer in pairs(self.observers) do
    observer(self)
  end
end

---@param self cds.ProgressReport
---@return cds.ProgressPhase?
local function running(self)
  for _, phase in ipairs(self.phases) do
    if phase.status == "running" then
      return phase
    end
  end
  return nil
end

--- Ends the running phase, if any, as done.
---@param self cds.ProgressReport
local function settle(self)
  local phase = running(self)
  if phase then
    phase.status, phase.ended = "done", self.now()
  end
end

--- Starts the phase called `name`, ending the one running; `of` is the
--- units the phase will count, for a bar. Begun again under the running
--- phase's own name, the phase stays running and takes the count given,
--- so a stage that learns the size late can say it.
---@param name string
---@param of? integer
function Report:begin(name, of)
  local current = running(self)
  if current and current.name == name then
    current.of = of or current.of
    changed(self)
    return
  end
  settle(self)
  local phase
  for _, candidate in ipairs(self.phases) do
    if candidate.name == name and candidate.status == "pending" then
      phase = candidate
      break
    end
  end
  if not phase then
    phase = { name = name, status = "pending", count = 0 }
    self.phases[#self.phases + 1] = phase
  end
  phase.status, phase.started, phase.count, phase.of = "running", self.now(), 0, of
  changed(self)
end

--- Counts `n` more units (one unless given) on the running phase.
---@param n? integer
function Report:tick(n)
  local phase = running(self)
  if phase then
    phase.count = phase.count + (n or 1)
    changed(self)
  end
end

--- Ends the running phase.
function Report:done()
  settle(self)
  changed(self)
end

--- Ends the running phase and the report: the title says "done in".
function Report:finish()
  settle(self)
  self.mode, self.ended = "done", self.now()
  changed(self)
end

--- Ends the report on an error: the running phase carries it.
---@param err string
function Report:fail(err)
  local phase = running(self)
  if phase then
    phase.status, phase.ended, phase.err = "failed", self.now(), err
  end
  self.mode, self.ended = "failed", self.now()
  changed(self)
end

--- Notes a moment by name: a draw, a step outside the phases.
---@param name string
function Report:mark(name)
  self.events[#self.events + 1] = { at = self.now() - self.started, kind = "mark", name = name }
  changed(self)
end

--- Notes that the main loop was blocked for `ms` milliseconds ending now,
--- under the phase running.
---@param ms integer
function Report:block(ms)
  local phase = running(self)
  self.events[#self.events + 1] =
    { at = self.now() - ms - self.started, kind = "block", name = phase and phase.name or "", duration = ms }
  changed(self)
end

---@return boolean
function Report:finished()
  return self.mode ~= "running"
end

--- Milliseconds since the report began, to its end once ended.
---@return integer
function Report:elapsed()
  return (self.ended or self.now()) - self.started
end

--- Calls `fn` with the report on every change; the function returned
--- stops that.
---@param fn fun(report: cds.ProgressReport)
---@return fun()
function Report:subscribe(fn)
  self.next_observer = self.next_observer + 1
  local id = self.next_observer
  self.observers[id] = fn
  return function()
    self.observers[id] = nil
  end
end

---@class cds.ProgressRow
---@field at integer
---@field kind "phase"|"mark"|"block"|"end"
---@field name string
---@field duration? integer

--- The run laid out in time: each phase with its length, each mark, each
--- block, and the end, by when they started.
---@return cds.ProgressRow[]
function Report:timeline()
  return lines.timeline(self)
end

--- The timeline as lines: the title with the outcome, then one row each,
--- the time from the start at the left and a length where there is one.
---@return string[]
function Report:timeline_lines()
  return lines.timeline_lines(self)
end

--- The report as lines `width` columns wide: the title with the elapsed
--- time (or "done in", or "failed") at the right edge, then one line per
--- phase.
---@param width integer
---@return string[]
function Report:lines(width)
  return lines.lines(self, width)
end

return require("cds.module").wrap("progress", M)
