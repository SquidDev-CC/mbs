return {
  description = "Replaces the textutils pagers with something akin to less",

  dependencies = {},

  settings = {
    {
      name = "mbs.pager.enabled",
      description = "Whether the alternative pager is enabled.",
      default = true,
      type = "boolean",
    },
    {
      name = "mbs.pager.mode",
      description = "The mode for the alternative pager.",
      default = "default",
    },
  },

  enabled = function() return settings.get("mbs.pager.enabled") end,

  setup = function(path)
    local native_pprint, native_ptabulate = textutils.pagedPrint, textutils.pagedTabulate
    textutils.pagedPrint = function(text, free_lines)
      local mode = settings.get("mbs.pager.mode")
      if mode == "none" then
        return io.write(text .. "\n")
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
  end,
}
