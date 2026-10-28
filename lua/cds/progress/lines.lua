-- Private renderer for cds.progress: a report as the lines a dashboard or a
-- statusline shows, and as the timeline a reader asks for afterwards. The
-- report's lifecycle (phases begun, ticked, ended, marks and blocks noted)
-- is cds.progress's own; this module only reads a report, so it never
-- requires cds.progress and cds.progress requires it.
local M = {}

local BAR = 16

---@param ms integer
---@return string
local function seconds(ms)
  return ("%.1fs"):format(ms / 1000)
end

--- The run laid out in time: each phase with its length, each mark, each
--- block, and the end, by when they started.
---@param report cds.ProgressReport
---@return cds.ProgressRow[]
function M.timeline(report)
  local rows = {}
  local now = report.now()
  for _, phase in ipairs(report.phases) do
    if phase.started then
      rows[#rows + 1] = {
        at = phase.started - report.started,
        kind = "phase",
        name = phase.name,
        duration = (phase.ended or now) - phase.started,
      }
    end
  end
  for _, event in ipairs(report.events) do
    rows[#rows + 1] = { at = event.at, kind = event.kind, name = event.name, duration = event.duration }
  end
  if report.mode ~= "running" then
    rows[#rows + 1] = { at = report:elapsed(), kind = "end", name = report.mode, duration = report:elapsed() }
  end
  for i, row in ipairs(rows) do
    row.order = i
  end
  table.sort(rows, function(a, b)
    if a.at ~= b.at then
      return a.at < b.at
    end
    return a.order < b.order
  end)
  for _, row in ipairs(rows) do
    row.order = nil
  end
  return rows
end

--- The timeline as lines: the title with the outcome, then one row each,
--- the time from the start at the left and a length where there is one.
---@param report cds.ProgressReport
---@return string[]
function M.timeline_lines(report)
  local outcome
  if report.mode == "done" then
    outcome = "done in " .. seconds(report:elapsed())
  elseif report.mode == "failed" then
    outcome = "failed"
  else
    outcome = "running " .. seconds(report:elapsed())
  end
  local out = { report.title .. ": " .. outcome }
  for _, row in ipairs(M.timeline(report)) do
    local at = ("%6.2fs  "):format(row.at / 1000)
    if row.kind == "phase" then
      out[#out + 1] = at .. ("%-31s %4.2fs"):format(row.name, row.duration / 1000)
    elseif row.kind == "block" then
      out[#out + 1] = at
        .. ("%-31s %4.2fs"):format("  main loop blocked", row.duration / 1000)
        .. (row.name ~= "" and ("  during " .. row.name) or "")
    else
      out[#out + 1] = at .. row.name
    end
  end
  return out
end

---@param phase cds.ProgressPhase
---@return string
local function bar(phase)
  local filled = 0
  if phase.count > 0 then
    filled = math.max(1, math.floor(phase.count * BAR / phase.of))
  end
  filled = math.min(filled, BAR)
  return "[" .. ("█"):rep(filled) .. ("░"):rep(BAR - filled) .. "] " .. phase.count .. "/" .. phase.of
end

---@param phase cds.ProgressPhase
---@param now integer
---@return string
local function phase_line(phase, now)
  if phase.status == "pending" then
    return "· " .. phase.name
  elseif phase.status == "running" then
    return "▸ " .. phase.name .. (phase.of and (" " .. bar(phase)) or "")
  elseif phase.status == "failed" then
    return "✗ " .. phase.name .. ": " .. (phase.err or "failed")
  end
  return "✓ " .. phase.name .. " " .. seconds((phase.ended or now) - (phase.started or now))
end

--- The report as lines `width` columns wide: the title with the elapsed
--- time (or "done in", or "failed") at the right edge, then one line per
--- phase.
---@param report cds.ProgressReport
---@param width integer
---@return string[]
function M.lines(report, width)
  local right
  if report.mode == "done" then
    right = "done in " .. seconds(report:elapsed())
  elseif report.mode == "failed" then
    right = "failed"
  else
    right = seconds(report:elapsed())
  end
  local pad = math.max(1, width - #report.title - #right)
  local out = { report.title .. (" "):rep(pad) .. right }
  local now = report.now()
  for _, phase in ipairs(report.phases) do
    out[#out + 1] = phase_line(phase, now)
  end
  return out
end

return M
