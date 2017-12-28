return {
  description = "Replaces the shell with an advanced version.",

  dependencies = {
    "bin/clear.lua",
    "bin/shell.lua",
    "lib/scroll_window.lua",
  },

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
    }
  },

  enabled = function() return settings.get("mbs.shell.enabled") end,

  setup = function(path)
    os.loadAPI(fs.combine(path, "lib/scroll_window.lua"))

    shell.setAlias("shell", fs.combine(path, "bin/shell.lua"))
    shell.setAlias("shell.lua", fs.combine(path, "bin/shell.lua"))
    shell.setAlias("sh", fs.combine(path, "bin/shell.lua"))

    shell.setAlias("clear", fs.combine(path, "bin/clear.lua"))
    shell.setAlias("clear.lua", fs.combine(path, "bin/clear.lua"))
  end,

  startup = function()
    shell.run("shell")
    shell.exit()
  end,
}
