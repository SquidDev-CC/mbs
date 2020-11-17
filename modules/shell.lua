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
    "bin/shell-worker.lua",
    "lib/scroll_window.lua",
    "lib/stack_trace.lua",
  },

  -- When updating the defaults, one should also update bin/shell.lua
  settings = {
    {
      name = "mbs.shell.enabled",
      description = "Whether the extended shell is enabled.",
      default = true,
      type = "boolean",
    },
    {
      name = "mbs.shell.history_file",
      description = "The file to save history to. Set to false to disable.",
      default = ".shell_history",
      type = "string",
    },
    {
      name = "mbs.shell.history_max",
      description = "The maximum size of the history file",
      default = 1e4,
      type = "number",
    },
    {
      name = "mbs.shell.scroll_max",
      description = "The maximum size of the scrollback",
      default = 1e3,
      type = "number",
    },
    {
      name = "mbs.shell.traceback",
      description = "Show an error traceback when a program errors",
      default = true,
      type = "boolean",
    },
  },

  enabled = function() return settings.get("mbs.shell.enabled") end,

  setup = function(path)
    lib_load(path, "scroll_window")
    lib_load(path, "stack_trace")

    shell.setAlias("shell", "/" .. fs.combine(path, "bin/shell.lua"))
    shell.setAlias("clear", "/" .. fs.combine(path, "bin/clear.lua"))

    local expect = require "cc.expect".expect
    function os.run(env, path, ...)
      expect(1, env, "table")
      expect(2, path, "string")
  
      setmetatable(env, { __index = _G })
      local func, err = loadfile(path, nil, env)
      if not func then 
        printError(err)
        return false
      end 

      local ok, err
      if settings.get("mbs.shell.traceback") then
        local arg = table.pack(...)
        ok, err = stack_trace.xpcall_with(function() return func(table.unpack(arg, 1, arg.n)) end)
      else
        ok, err = pcall(func, ...)
      end

      if not ok and err and err ~= "" then printError(err) end
      return ok
  end

    shell.setCompletionFunction(fs.combine(path, "bin/shell-wrapper.lua"), function(shell, index, text, previous)
      if index == 1 then return shell.completeProgram(text) end
    end)
  end,

  startup = function(path)
    local fn, err = loadfile(fs.combine(path, "bin/shell-worker.lua"), _ENV)
    if not fn then error(err) end

    fn()
  end,
}
