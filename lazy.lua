-- The library as a lazy.nvim plugin: lua/cds/ on the runtimepath, loaded on
-- its first require, with the vocabulary rock as its own dependency, so a
-- plugin that takes cds-lua has cds.fp, cds.result and cds.module as well.
-- Lazy builds Gumbo through its rockspec and exposes its Lua/native modules.
return {
  "cds-io/cds-lua",
  lazy = true,
  dependencies = {
    { "cds-io/cds-lua-fp", lazy = true },
    {
      url = "https://gitlab.com/craigbarnes/lua-gumbo.git",
      name = "lua-gumbo",
    },
  },
}
