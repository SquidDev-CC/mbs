return {
  description = "Replaces the Lua REPL with an advanced version.",

  dependencies = {
    "bin/lua.lua",
  },

  -- When updating the defaults, one should also update bin/lua.lua
  settings = {
    {
      name = "mbs.lua.enabled",
      description = "Whether the extended Lua REPL is enabled.",
      default = true,
    },
    {
      name = "mbs.lua.history_file",
      description = "The file to save history to. Set to false to disable.",
      default = ".lua_history",
    },
    {
      name = "mbs.lua.history_max",
      description = "The maximum size of the history file",
      default = 1e4,
    }
  },

  enabled = function() return settings.get("mbs.lua.enabled") end,

  setup = function(path)
    if settings.get("mbs.lua.enabled") then
      shell.setAlias("lua", "/" .. fs.combine(path, "bin/lua.lua"))
    end
  end
}
