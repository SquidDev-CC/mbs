local function lib_load(path, name)
  if not _G[name] then
    os.loadAPI(fs.combine(path, "lib/" .. name .. ".lua"))
    if not _G[name] then _G[name] = _G[name .. ".lua"] end
  end
end

return {
  description = "Replaces the Lua REPL with an advanced version.",

  dependencies = {
    "bin/lua.lua",
    "lib/stack_trace.lua",
  },

  -- When updating the defaults, one should also update bin/lua.lua
  settings = {
    {
      name = "mbs.lua.enabled",
      description = "Whether the extended Lua REPL is enabled.",
      default = true,
      type = "boolean",
    },
    {
      name = "mbs.lua.history_file",
      description = "The file to save history to. Set to false to disable.",
      default = ".lua_history",
      type = "string",
    },
    {
      name = "mbs.lua.history_max",
      description = "The maximum size of the history file",
      default = 1e4,
      type = "number",
    },
    {
      name = "mbs.lua.traceback",
      description = "Show an error traceback when an input errors",
      default = true,
      type = "boolean",
    },
    {
      name = "mbs.lua.pretty_height",
      description = "The height to fit the pretty-printer output to. Set to "
        .. "false to disable, true to use the terminal height or a number for a constant height.",
      default = true,
    },
    {
      name = "mbs.lua.highlight",
      description = "Whether to apply syntax highlighting to the REPL's input.",
      default = true,
      type = "boolean",
    },
  },

  enabled = function() return settings.get("mbs.lua.enabled") end,

  setup = function(path)
    lib_load(path, "stack_trace")

    shell.setAlias("lua", "/" .. fs.combine(path, "bin/lua.lua"))
  end,
}
