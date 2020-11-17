--- Additional readline

local function lib_load(path, name)
  if not _G[name] then
    os.loadAPI(fs.combine(path, "lib/" .. name .. ".lua"))
    if not _G[name] then _G[name] = _G[name .. ".lua"] end
  end
end

return {
  description =
    "This module extends the default read function, adding keybindings similar to " ..
    "those provided by Emacs or GNU readline as well as additional configuration options.",

  dependencies = {
    "lib/readline.lua",
  },

  settings = {
    {
      name = "mbs.readline.enabled",
      description = "Whether the readline module is enabled.",
      default = true,
      type = "boolean",
    },
    {
      name = "mbs.readline.complete_bg",
      description = "The background colour for completions.",
      default = "none",
    },
    {
      name = "mbs.readline.complete_fg",
      description = "The foreground colour for completions.",
      default = "grey",
    },
  },

  enabled = function() return settings.get("mbs.readline.enabled") end,

  setup = function(path)
    lib_load(path, "readline")

    -- Replace the default read function
    _G.read = function(replace_char, history, complete, default)
      if replace_char ~= nil and type(replace_char) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(replace_char) .. ")", 2)
      end
      if history ~= nil and type(history) ~= "table" then
        error("bad argument #2 (expected table, got " .. type(history) .. ")", 2)
      end
      if complete ~= nil and type(complete) ~= "function" then
        error("bad argument #3 (expected function, got " .. type(complete) .. ")", 2)
      end
      if default ~= nil and type(default) ~= "string" then
        error("bad argument #4 (expected string, got " .. type(default) .. ")", 2)
      end

      return readline.read {
        replace_char = replace_char,
        history = history,
        complete = complete,
        default = default,
      }
    end

  end,
}
