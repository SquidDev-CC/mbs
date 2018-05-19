return {
  description = "Replaces the Lua REPL with an advanced version.",

  dependencies = {
    "bin/lua.lua",
    "lib/stack_trace.lua"
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
    },
    {
      name = "mbs.lua.traceback",
      description = "Show an error traceback when an input errors",
      default = true,
    },
  },

  enabled = function() return settings.get("mbs.lua.enabled") end,

  setup = function(path)
    if not _G["stack_trace"] then
      os.loadAPI(fs.combine(path, "lib/stack_trace.lua"))
      if not _G["stack_trace"] then _G["stack_trace"] = _G["stack_trace.lua"] end
    end

    shell.setAlias("lua", "/" .. fs.combine(path, "bin/lua.lua"))
  end
}
