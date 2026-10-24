-- The texts the cds specs read. RFCs: five texts and an excerpt of the RFC
-- index, fetched from the RFC Editor (https://www.rfc-editor.org/rfc/rfcN.txt
-- and /rfc-index.txt) on 2026-10-19, with form feeds and the byte-order mark
-- removed, which is how a plugin stores a fetched text. The excerpt is the
-- index's header and the blocks for RFCs 14, 31, 61, 266 and 2616.
-- Resolved from this file's own directory so a spec runs from any working
-- directory.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local M = {
  rfc791 = "rfc791.txt",
  rfc1945 = "rfc1945.txt",
  rfc2616 = "rfc2616.txt",
  rfc3986 = "rfc3986.txt",
  rfc9110 = "rfc9110.txt",
  rfc_index = "rfc-index.txt",
  -- EIPs: ethereum/EIPs and ethereum/ERCs on GitHub (CC0), fetched 2026-10-20,
  -- and excerpts of eips.ethereum.org/all and ercs.ethereum.org/all keeping
  -- every status heading and a few rows each
  eip1 = "eip-1.md",
  eip1559 = "eip-1559.md",
  erc20 = "erc-20.md",
  eip20_moved = "eip-20-moved.md",
  erc1123 = "erc-1123.md", -- pandoc HTML tables and emphasis
  eips_all = "eips-all.html",
  ercs_all = "ercs-all.html",
  -- BIPs: bitcoin/bips on GitHub (each under its own licence, BSD-2-Clause
  -- or similar), fetched 2026-10-20, and the repository's README, the index
  bip32 = "bip-0032.mediawiki", -- a change log above the preamble, <pre> test vectors, <sub> in headings
  bip22 = "bip-0022.mediawiki", -- wikitables with captions and || cells, section links
  bip341 = "bip-0341.mediawiki", -- footnotes, named and reused, and a Requires field
  bip3 = "bip-0003.md", -- the markdown form, with its preamble in a fence
  bips_readme = "bips-README.mediawiki",
  -- SIMDs: solana-foundation/solana-improvement-documents on GitHub (CC0),
  -- fetched 2026-10-21, and the proposals directory as the contents API
  -- lists it, which is the index
  simd64 = "simd-0064-transaction-receipt.md", -- authors as a list, feature N/A
  simd1 = "simd-0001-simd-process.md",
  simd_related = "simd-0268-raise-cpi-nesting-limit.md", -- supersedes or extends another
  simd_listing = "simd-proposals.json",
  -- RFC subject tags: eleven rows of the RFC Editor's published build
  -- (https://rfc-editor.github.io/rfc-subject-tags/rfc-tags.csv, fetched
  -- 2026-10-23): quoted titles, two direct tags on one row, a four-level
  -- path, and an untagged row
  rfc_tags = "rfc-tags.csv",
  -- W3C technical reports (W3C Document License): excerpts of the Thing
  -- Description 1.1 (ReSpec) and CSS Grid 2 (Bikeshed), fetched 2026-10-23,
  -- cut as each file's leading comment says
  w3c_td = "w3c-wot-thing-description11.html",
  w3c_grid = "w3c-css-grid-2.html",
  w3c_tr = "w3c-tr.html", -- a dozen entries of www.w3.org/TR, every maturity and the odd rows
}

M.dir = here .. "/fixtures/"

---@param name string
---@return string[]
function M.read(name)
  local lines = {}
  for line in io.lines(M.dir .. name) do
    table.insert(lines, line)
  end
  return lines
end

--- The first entry whose `field` equals `value`.
---@generic T
---@param entries T[]
---@param field string
---@param value any
---@return T|nil
function M.find(entries, field, value)
  for _, e in ipairs(entries) do
    if e[field] == value then
      return e
    end
  end
end

return M
