-- Generates doc/cds-lua.txt with mini.doc (`make doc`) from the modules the
-- plugins call in common. The manual is the tagged block at the head of each
-- file; a public function's block renders under the module's name (fp.map,
-- Task:bind) with a tag of the class name (cds.fp.map(), cds.Task:bind()); a
-- local helper's block, a @generic line, a @field marked package and a module
-- class with no fields stay in the code. Types render as the annotations
-- spell them, aliases included, since mini.doc's own type reading stops at
-- the first comma of a function type's return list.
-- luacheck: globals MiniDoc
require("mini.doc").setup({ silent = true })

-- in the order the manual reads; the vocabulary and the needs check (fp,
-- result, module, needs) are the cds-lua-fp rock's own manual
local FILES = { "task", "async", "http", "redraw", "activity" }

---@param block table   -- a mini.doc block: an array of sections
---@param id string     -- "@tag"
---@return table[]      -- the block's sections of that kind
local function sections(block, id)
  local found = {}
  for _, section in ipairs(block) do
    if section.info.id == id then
      found[#found + 1] = section
    end
  end
  return found
end

---@param block table
---@return string   -- "fp", from lua/cds/fp.lua
local function module_of(block)
  return vim.fn.fnamemodify(block.parent.info.path, ":t:r")
end

-- a field the language server keeps to the file is not API
local HIDDEN = { package = true, private = true, protected = true }

--- The tag of a documented object: the module's class for `M`, the class
--- named for any other table (Task, Activity), so `M.map()` in fp.lua is
--- `cds.fp.map()` and `Task:bind()` is `cds.Task:bind()`.
---@param line string
---@param mod string
---@return string
local function tag_of(line, mod)
  local renamed = line:gsub("^M([.:])", "cds." .. mod .. "%1", 1)
  if renamed == line then
    renamed = "cds." .. line
  end
  return renamed
end

---@param block table
local function block_pre(block)
  if not block:has_lines() then
    return
  end
  local first = block.info.afterlines[1] or ""
  local header = #sections(block, "@tag") > 0
  local class = #sections(block, "@class") > 0
  -- a public function, or a value assigned on the module (M.map = M.bind)
  local api = first:match("^function ") or first:match("^%a[%w_]*[.:][%w_.]+%s*=")
  if first:match("^local ") and not header and not class then
    block:clear_lines() -- a helper of the file
    return
  end
  if api and not header then
    MiniDoc.default_hooks.block_pre(block) -- infers the tag and the signature
    local mod = module_of(block)
    for _, tag in ipairs(sections(block, "@tag")) do
      tag[1] = tag_of(tag[1], mod)
    end
    for _, signature in ipairs(sections(block, "@signature")) do
      signature[1] = signature[1]:gsub("^M%.", mod .. ".", 1)
    end
  end
  if class then
    local fields = 0
    for _, field in ipairs(sections(block, "@field")) do
      if HIDDEN[field[1]:match("^%s*(%S+)")] then
        field:clear_lines()
      else
        fields = fields + 1
      end
    end
    if fields == 0 then
      for _, section in ipairs(sections(block, "@class")) do
        section:clear_lines() -- the module's own class: a name, nothing to list
      end
    end
  end
end

--- A declaration line split: the note after ` -- `, then the rest.
---@param line string
---@return string rest
---@return string note   -- "" without one
local function noted(line)
  local rest, note = line:match("^(.-)%s+%-%-%s+(.*)$")
  return rest or line, note or ""
end

--- A line that names then types (`@param`, `@field`, `@alias`) rendered as
--- `{name} (optional) (type) note`.
---@param section table
local function name_then_type(section)
  local rest, note = noted(section[1])
  local name, kind = rest:match("^%s*(%S+)%s*(.-)%s*$")
  local optional = ""
  if name:sub(-1) == "?" then
    name, optional = name:sub(1, -2), " `(optional)`"
  end
  local typed = kind ~= "" and (" `(" .. kind .. ")`") or ""
  section[1] = ("{%s}%s%s%s"):format(name, optional, typed, note ~= "" and " " .. note or "")
end

--- A `@return` line, `type [name]`, rendered as `(type) name note`. The last
--- word is the name when it is a bare identifier that no comma, colon or
--- bar joins to the type (`U? value`, but `fun(): any, any` names nothing).
---@param section table
local function type_then_name(section)
  local rest, note = noted(section[1])
  local kind, name = rest:match("^%s*(.-)%s+([%a_][%w_]*)%s*$")
  if not kind or kind:match("[,:|]$") then
    kind, name = vim.trim(rest), ""
  end
  section[1] = ("`(%s)`%s%s"):format(kind, name ~= "" and " " .. name or "", note ~= "" and " " .. note or "")
end

---@param section table
local function section_pre(section)
  if section.info.id == "@generic" then
    section:clear_lines() -- a type variable; the parameters say what it ranges over
  elseif section.info.id == "@text" and section[1] == "" then
    section:remove(1) -- `---@text` on its own line, so the server reads the prose too
  end
end

---@param section table
local function heading(section, text)
  section:insert(1, text .. " ~")
end

---@param block table
local function block_post(block)
  if not block:has_lines() then
    return
  end
  local first = {}
  local tags = 0
  for _, section in ipairs(sections(block, "@tag")) do
    block:remove(section.parent_index)
    tags = tags + 1
    block:insert(tags, section)
  end
  for _, section in ipairs(block) do
    local id = section.info.id
    if #section > 0 and (id == "@param" or id == "@field" or id == "@return" or id == "@alias") and not first[id] then
      first[id] = true
      heading(
        section,
        ({ ["@param"] = "Parameters", ["@field"] = "Fields", ["@return"] = "Return", ["@alias"] = "Alias" })[id]
      )
    end
  end
  -- a module's header follows the file separator; the rule under it is noise
  if #sections(block, "@toc_entry") == 0 then
    block:insert(1, { string.rep("-", 78) })
  end
  block:insert({ "" })
end

local inputs = vim.tbl_map(function(name)
  return "lua/cds/" .. name .. ".lua"
end, FILES)
MiniDoc.generate(inputs, "doc/cds-lua.txt", {
  hooks = {
    block_pre = block_pre,
    section_pre = section_pre,
    sections = vim.tbl_extend("force", MiniDoc.default_hooks.sections, {
      ["@param"] = name_then_type,
      ["@field"] = name_then_type,
      ["@alias"] = name_then_type,
      ["@return"] = type_then_name,
    }),
    block_post = block_post,
  },
})
