-- The library as a lazy.nvim plugin: lua/cds/ on the runtimepath, loaded on
-- its first require, with the vocabulary rock as its own dependency, so a
-- plugin that takes cds-lua has cds.fp, cds.result and cds.module as well.
return {
  "cds-io/cds-lua",
  lazy = true,
  dependencies = { { "cds-io/cds-lua-fp", lazy = true } },
}
