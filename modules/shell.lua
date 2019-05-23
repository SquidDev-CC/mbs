local function lib_load(path, name)
  if not _G[name] then
    os.loadAPI(fs.combine(path, "lib/" .. name .. ".lua"))
    if not _G[name] then _G[name] = _G[name .. ".lua"] end
  end
end

return {
  description = "Replaces the shell with an advanced version.",

  dependencies = {
    "bin/clear.lua",
    "bin/shell.lua",
    "lib/blit_window.lua",
    "lib/scroll_window.lua",
    "lib/stack_trace.lua",
  },

  -- When updating the defaults, one should also update bin/shell.lua
  settings = {
    {
      name = "mbs.shell.enabled",
      description = "Whether the extended shell is enabled.",
      default = true,
    },
    {
      name = "mbs.shell.history_file",
      description = "The file to save history to. Set to false to disable.",
      default = ".shell_history",
    },
    {
      name = "mbs.shell.history_max",
      description = "The maximum size of the history file",
      default = 1e4,
    },
    {
      name = "mbs.shell.scroll_max",
      description = "The maximum size of the scrollback",
      default = 1e3,
    },
    {
      name = "mbs.shell.traceback",
      description = "Show an error traceback when a program errors",
      default = true,
    },
    {
      name = "mbs.shell.require_path",
      description = "The path from that require will use by default. Set to false to use the CraftOS default.",
      default = false,
    },
    {
      name = "mbs.shell.strict_globals",
      description = "When set to true the shell will throw errors when programs attempt to define new globals in their environment. If you really want globals then you should use _G instead.",
      default = false,
    },
  },

  enabled = function() return settings.get("mbs.shell.enabled") end,

  setup = function(path)
    lib_load(path, "scroll_window")
    lib_load(path, "blit_window")
    lib_load(path, "stack_trace")

    shell.setAlias("shell", "/" .. fs.combine(path, "bin/shell.lua"))
    shell.setAlias("clear", "/" .. fs.combine(path, "bin/clear.lua"))

    shell.setCompletionFunction(fs.combine(path, "bin/shell.lua"), function(shell, index, text, previous)
      if index == 1 then return shell.completeProgram(text) end
    end)
  end,

  startup = function(path)
    local fn, err = loadfile(fs.combine(path, "bin/shell.lua"), _ENV)
    if not fn then error(err) end

    fn()

    shell.exit()
  end,
}
