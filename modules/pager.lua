return {
  description = "Replaces the textutils pagers with something akin to less",

  dependencies = {
    "bin/help.lua"
  },

  settings = {
    {
      name = "mbs.pager.enabled",
      description = "Whether the alternative pager is enabled.",
      default = true,
    },
    {
      name = "mbs.pager.mode",
      description = "The mode for the alternative pager.",
      default = "default",
    }
  },

  enabled = function() return settings.get("mbs.pager.enabled") end,

  setup = function(path)
    shell.setAlias("help", "/" .. fs.combine(path, "bin/help.lua"))
    shell.setCompletionFunction(fs.combine(path, "bin/help.lua"), function(shell, index, text, previous)
      if index == 1 then return help.completeTopic(text) end
    end)

    local native_pprint, native_ptabulate = textutils.pagedPrint, textutils.pagedTabulate
    textutils.pagedPrint = function(text, free_lines)
      local mode = settings.get("mbs.pager.mode")
      if mode == "none" then
        return print(text)
      else
        return native_pprint(text, free_lines)
      end
    end

    textutils.pagedTabulate = function(...)
      local mode = settings.get("mbs.pager.mode")
      if mode == "none" then
        return textutils.tabulate(...)
      else
        return native_ptabulate(...)
      end
    end
  end
}
