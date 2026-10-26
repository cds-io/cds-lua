---@tag cds.entities
---@toc_entry HTML character references
---@text
--- Decode HTML character references once, or encode a Unicode code point as UTF-8. XML readers may share the
--- UTF-8 encoder while keeping their own named-entity rules.

-- HTML character references shared by article rendering and feed discovery.
local M = {}

-- The named entities article HTML uses, by code point. `nbsp` is a plain
-- space, so the collapse and the wrap treat it as one, and `shy` (0) decodes
-- to nothing.
-- stylua: ignore
local named = {
    amp = 38, lt = 60, gt = 62, quot = 34, apos = 39, nbsp = 32, shy = 0,
    mdash = 0x2014, ndash = 0x2013, lsquo = 0x2018, rsquo = 0x2019, ldquo = 0x201C, rdquo = 0x201D,
    sbquo = 0x201A, bdquo = 0x201E, hellip = 0x2026, middot = 0xB7, bull = 0x2022, laquo = 0xAB, raquo = 0xBB,
    copy = 0xA9, reg = 0xAE, trade = 0x2122, times = 0xD7, divide = 0xF7, plusmn = 0xB1, deg = 0xB0,
    rarr = 0x2192, larr = 0x2190, uarr = 0x2191, darr = 0x2193, para = 0xB6, sect = 0xA7,
    euro = 0x20AC, pound = 0xA3, yen = 0xA5, cent = 0xA2, micro = 0xB5,
    frac12 = 0xBD, frac14 = 0xBC, frac34 = 0xBE, sup2 = 0xB2, sup3 = 0xB3, iexcl = 0xA1, iquest = 0xBF,
}

-- The HTML 4 Latin-1 letters, U+00C0 to U+00FF in order; the two slots
-- that hold no letter are times and divide, named above.
-- stylua: ignore
local latin1 = {
    "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil",
    "Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml",
    "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", false,
    "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
    "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil",
    "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
    "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", false,
    "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
}
for i, name in ipairs(latin1) do
  if name then
    named[name] = 0xBF + i
  end
end

--- A code point as UTF-8 (Lua 5.1 has no utf8 library).
---@param cp integer
---@return string
function M.utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

--- Entities decoded, in one pass, so `&amp;lt;` is the text `&lt;`. An entity
--- with no decoding (an unknown name, a number past U+10FFFF, a hex form with
--- no hex digits) stays as written.
---@param s string
---@return string
function M.entities(s)
  return (
    s:gsub("&(#?[xX]?%w+);", function(e)
      local cp
      if e:match("^#[xX]") then
        cp = tonumber(e:sub(3), 16)
      elseif e:sub(1, 1) == "#" then
        cp = tonumber(e:sub(2))
      else
        cp = named[e]
        if cp == 0 then
          return ""
        end
      end
      if cp and cp <= 0x10FFFF then
        return M.utf8(cp)
      end
      return "&" .. e .. ";"
    end)
  )
end

return M
