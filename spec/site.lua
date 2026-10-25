-- The reference site: `nvim -l spec/site.lua` writes site/modules/, one
-- Markdown page per module under lua/cds/, from the language server's own
-- export of the annotations (`--doc`), plus the modules index. The pages
-- carry Jekyll front matter for the just-the-docs theme; the Pages workflow
-- builds and publishes them on every push to main, and site/modules/ stays
-- out of git.
local luals = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/luals.lua")
local root = luals.root()

-- The export -----------------------------------------------------------------

local out = vim.fn.tempname()
vim.fn.mkdir(out, "p")
local result =
  vim.system({ luals.server(), "--doc", root .. "/lua", "--doc_out_path", out, "--configpath", luals.config() }):wait()
if result.code ~= 0 then
  io.stderr:write(result.stdout or "", result.stderr or "")
  os.exit(result.code)
end
---@type table[]   -- every type the server knows; the library's are filed under cds/
local entries = vim.json.decode(table.concat(vim.fn.readfile(out .. "/doc.json"), "\n"))

---@param file string   -- "cds/html/blocks.lua"
---@return string       -- "cds.html.blocks"
local function module_name(file)
  return (file:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", "."))
end

-- every module: a page each, with or without declared types
---@type string[]   -- "cds/fp.lua", sorted
local files = vim.tbl_map(function(path)
  return path:sub(#root + #"/lua/" + 1)
end, vim.fn.glob(root .. "/lua/cds/**/*.lua", true, true))
table.sort(files)

---@type table<string, table[]>   -- file to its types, in source order
local types_of = {}
---@type table<string, string>    -- class or alias name to the module that declares it
local module_of = {}
for _, entry in ipairs(entries) do
  local define = entry.defines and entry.defines[1]
  if define and define.file and define.file:match("^cds/") then
    types_of[define.file] = types_of[define.file] or {}
    table.insert(types_of[define.file], entry)
    module_of[entry.name] = module_name(define.file)
  end
end
for _, types in pairs(types_of) do
  table.sort(types, function(a, b)
    return a.defines[1].start[1] < b.defines[1].start[1]
  end)
end
local modules = {}
for _, file in ipairs(files) do
  modules[module_name(file)] = true
end

---@param field table
---@return boolean
local function is_function(field)
  return field.extends ~= nil and field.extends.type == "function"
end

--- The class a module's page opens with: the one named as the module, or the
--- one declaring the most functions (cds.Task in task.lua).
---@param name string
---@param types table[]
---@return table?
local function main_class(name, types)
  local best, most = nil, 0
  for _, entry in ipairs(types) do
    if entry.name == name then
      return entry
    end
    local count = #vim.tbl_filter(is_function, entry.fields or {})
    if entry.defines[1].type == "doc.class" and count > most then
      best, most = entry, count
    end
  end
  return best
end

---@type table<string, table>   -- file to the class its page opens with
local main_of = {}
---@type table<string, true>    -- the names of those classes
local is_main = {}
for _, file in ipairs(files) do
  local main = main_class(module_name(file), types_of[file] or {})
  if main then
    main_of[file] = main
    is_main[main.name] = true
  end
end

-- The prose -------------------------------------------------------------------

--- A module's introduction: the tagged block at the head of its file that
--- carries its own tag, or the plain comment the file opens with.
---@param file string
---@param name string
---@return string[] lines
local function intro(file, name)
  local blocks, block = {}, {}
  for _, line in ipairs(vim.fn.readfile(root .. "/lua/" .. file)) do
    if line:match("^%-%-") then
      block[#block + 1] = line
    elseif line == "" then
      if #block > 0 then
        blocks[#blocks + 1], block = block, {}
      end
    else
      break
    end
  end
  if #block > 0 then
    blocks[#blocks + 1] = block
  end
  local chosen = blocks[1] or {}
  for _, candidate in ipairs(blocks) do
    if vim.tbl_contains(candidate, "---@tag " .. name) then
      chosen = candidate
    end
  end
  local lines = {}
  for _, line in ipairs(chosen) do
    if not line:match("^%-%-%-@") then
      lines[#lines + 1] = (line:gsub("^%-%-%-? ?", ""))
    end
  end
  return lines
end

--- A help tag as a link: a module to its page, a member to its heading, the
--- library's own tag to the front page; anything else stays as code.
---@param tag string   -- "cds.Task:run()"
---@return string
local function link(tag)
  if tag == "cds-lua" then
    return "[cds-lua](../)"
  end
  if modules[tag] then
    return ("[%s](%s.html)"):format(tag, tag)
  end
  local class, member = tag:gsub("%(%)$", ""):match("^(.+)[.:]([%w_]+)$")
  if class and module_of[class] then
    local id = is_main[class] and member or (class .. "." .. member)
    return ("[%s](%s.html#%s)"):format(tag, module_of[class], id)
  end
  return "`" .. tag .. "`"
end

--- Help prose as Markdown: `>lua` to `<` becomes a fenced block, `|tag|` a
--- link, and the server's appended parameter notes are cut.
---@param lines string[]
---@return string
local function markdown(lines)
  local md, fenced = {}, false
  for _, line in ipairs(lines) do
    if line:match("^@%*") then
      break
    end
    if line:match(">lua%s*$") then
      local before = line:gsub("%s*>lua%s*$", "")
      if before ~= "" then
        md[#md + 1] = before
      end
      md[#md + 1] = ""
      md[#md + 1] = "```lua"
      fenced = true
    elseif fenced and line:match("^<%s*$") then
      md[#md + 1] = "```"
      md[#md + 1] = ""
      fenced = false
    elseif fenced then
      -- the help's blank line after `>lua` is spacing there, a blank first line here
      if not (line == "" and md[#md] == "```lua") then
        md[#md + 1] = (line:gsub("^  ", ""))
      end
    elseif line:match("^  ") then
      md[#md + 1] = "  " .. line -- an indented example: Markdown's indented code block
    else
      md[#md + 1] = (line:gsub("|([%w%.:_%-()]+)|", link))
    end
  end
  if fenced then
    md[#md + 1] = "```"
  end
  return vim.trim(table.concat(md, "\n"))
end

---@param desc string?   -- the server's description, each line with a leading space
---@return string
local function described(desc)
  if not desc or desc == "" then
    return ""
  end
  return markdown(vim.tbl_map(function(line)
    return (line:gsub("^ ", ""))
  end, vim.split(desc, "\n")))
end

-- The pages -------------------------------------------------------------------

---@param s string
---@return string   -- safe inside a Markdown table cell
local function cell(s)
  return (s:gsub("|", "\\|"):gsub("\n", " "))
end

---@param field table
---@param id string
---@param level string   -- "###"
---@return string[]
local function function_section(field, id, level)
  local lines = { ("%s %s {#%s}"):format(level, field.name, id), "" }
  lines[#lines + 1] = "```lua"
  lines[#lines + 1] = field.extends.view
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""
  local desc = described(field.rawdesc or field.desc)
  if desc ~= "" then
    lines[#lines + 1] = desc
    lines[#lines + 1] = ""
  end
  local args = vim.tbl_filter(function(arg)
    return arg.name ~= "self"
  end, field.extends.args or {})
  if #args > 0 then
    lines[#lines + 1] = "Parameters:"
    lines[#lines + 1] = ""
    for _, arg in ipairs(args) do
      local note = arg.desc and (": " .. described(arg.desc)) or ""
      lines[#lines + 1] = ("- `%s` `%s`%s"):format(arg.name, arg.view, note)
    end
    lines[#lines + 1] = ""
  end
  local returns = field.extends.returns or {}
  if #returns > 0 then
    lines[#lines + 1] = "Returns:"
    lines[#lines + 1] = ""
    for _, ret in ipairs(returns) do
      local name = ret.name and (" " .. ret.name) or ""
      local note = ret.desc and (": " .. described(ret.desc)) or ""
      lines[#lines + 1] = ("- `%s`%s%s"):format(ret.view, name, note)
    end
    lines[#lines + 1] = ""
  end
  return lines
end

---@param fields table[]
---@return string[]
local function fields_table(fields)
  local lines = { "| Field | Type | Description |", "|---|---|---|" }
  for _, field in ipairs(fields) do
    lines[#lines + 1] = ("| `%s` | `%s` | %s |"):format(field.name, cell(field.view), cell(described(field.desc)))
  end
  lines[#lines + 1] = ""
  return lines
end

---@param entry table
---@return table[] fields   -- the public ones, in source order
local function public_fields(entry)
  local fields = vim.tbl_filter(function(field)
    return field.visible == nil or field.visible == "public"
  end, entry.fields or {})
  table.sort(fields, function(a, b)
    return a.start[1] < b.start[1]
  end)
  return fields
end

---@param file string
---@return string[] lines   -- the page
---@return string summary   -- its first line of prose
local function page(file)
  local name = module_name(file)
  local types = types_of[file] or {}
  local prose = intro(file, name)
  local lines = { "---", "title: " .. name, "parent: Modules", "---", "", "# " .. name, "" }
  local body = markdown(prose)
  if body ~= "" then
    lines[#lines + 1] = body
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = ("Source: [`lua/%s`](https://github.com/cds-io/cds-lua/blob/main/lua/%s)"):format(file, file)
  lines[#lines + 1] = ""
  local main = main_of[file]
  if main then
    local functions = vim.tbl_filter(is_function, public_fields(main))
    local values = vim.tbl_filter(function(field)
      return not is_function(field)
    end, public_fields(main))
    if #functions > 0 then
      lines[#lines + 1] = "## Functions"
      lines[#lines + 1] = ""
      for _, field in ipairs(functions) do
        vim.list_extend(lines, function_section(field, field.name, "###"))
      end
    end
    if #values > 0 then
      lines[#lines + 1] = "## Values"
      lines[#lines + 1] = ""
      for _, field in ipairs(values) do
        lines[#lines + 1] = ("### %s {#%s}"):format(field.name, field.name)
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("`%s`"):format(field.view)
        lines[#lines + 1] = ""
        local desc = described(field.rawdesc or field.desc)
        if desc ~= "" then
          lines[#lines + 1] = desc
          lines[#lines + 1] = ""
        end
      end
    end
  end
  local others = vim.tbl_filter(function(entry)
    return entry ~= main
  end, types)
  if #others > 0 then
    lines[#lines + 1] = "## Types"
    lines[#lines + 1] = ""
    for _, entry in ipairs(others) do
      local define = entry.defines[1]
      lines[#lines + 1] = ("### %s {#%s}"):format(entry.name, entry.name)
      lines[#lines + 1] = ""
      if define.type == "doc.alias" then
        lines[#lines + 1] = ("Alias of `%s`"):format(define.view)
        lines[#lines + 1] = ""
      end
      local desc = described(define.rawdesc or define.desc)
      if desc ~= "" then
        lines[#lines + 1] = desc
        lines[#lines + 1] = ""
      end
      local fields = public_fields(entry)
      local data = vim.tbl_filter(function(field)
        return not is_function(field)
      end, fields)
      if #data > 0 then
        vim.list_extend(lines, fields_table(data))
      end
      for _, field in ipairs(vim.tbl_filter(is_function, fields)) do
        vim.list_extend(lines, function_section(field, entry.name .. "." .. field.name, "####"))
      end
    end
  end
  local paragraph = {}
  for _, line in ipairs(prose) do
    if line == "" then
      break
    end
    paragraph[#paragraph + 1] = line
  end
  local text = table.concat(paragraph, " ")
  return lines, text:match("^(.-%.)%s") or text
end

local dir = root .. "/site/modules"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir, "p")
local index = {
  "---",
  "title: Modules",
  "nav_order: 2",
  "has_children: true",
  "---",
  "",
  "# Modules",
  "",
  "One page per file under `lua/cds/`, generated from the annotations by the language server.",
  "",
  "| Module | |",
  "|---|---|",
}
for _, file in ipairs(files) do
  local name = module_name(file)
  local lines, summary = page(file)
  vim.fn.writefile(vim.split(table.concat(lines, "\n"), "\n"), ("%s/%s.md"):format(dir, name))
  index[#index + 1] = ("| [%s](%s.html) | %s |"):format(name, name, cell(markdown({ summary })))
end
index[#index + 1] = ""
vim.fn.writefile(index, dir .. "/index.md")
print(("%d module pages in site/modules/"):format(#files))
