
local multishell = multishell
local parentShell = shell

if multishell then
  multishell.setTitle(multishell.getCurrent(), "shell")
end

local bExit = false
local sDir = (parentShell and parentShell.dir()) or ""
local sPath = (parentShell and parentShell.path()) or ".:/rom/programs"
local tAliases = (parentShell and parentShell.aliases()) or {}
local tCompletionInfo = (parentShell and parentShell.getCompletionInfo()) or {}
local tProgramStack = {}
local history = parentShell and type(parentShell.history) == "function" and parentShell.history()
local fWrapper = nil

local shell = {}
local function createShellEnv(sDir)
  local tEnv = {}
  tEnv["shell"] = shell
  tEnv["multishell"] = multishell

  if fWrapper then
    if read then tEnv.read = fWrapper(read) end
    if readline and readline.read then tEnv.readline = { read = fWrapper(readline.read) } end
  end

  local package = {}
  package.loaded = {
    _G = _G,
    bit32 = bit32,
    coroutine = coroutine,
    math = math,
    package = package,
    string = string,
    table = table,
  }
  package.path = settings.get('mbs.shell.require_path') or
    "?;?.lua;?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"
  if turtle then
    package.path = package.path..";/rom/modules/turtle/?;/rom/modules/turtle/?.lua;/rom/modules/turtle/?/init.lua"
  elseif command then
    package.path = package.path..";/rom/modules/command/?;/rom/modules/command/?.lua;/rom/modules/command/?/init.lua"
  end
  package.config = "/\n;\n?\n!\n-"
  package.preload = {}
  package.loaders = {
    function(name)
      if package.preload[name] then
        return package.preload[name]
      else
        return nil, "no field package.preload['" .. name .. "']"
      end
    end,
    function(name)
      local fname = string.gsub(name, "%.", "/")
      local sError = ""
      for pattern in string.gmatch(package.path, "[^;]+") do
        local sPath = string.gsub(pattern, "%?", fname)
        if sPath:sub(1,1) ~= "/" then
          sPath = fs.combine(sDir, sPath)
        end
        if fs.exists(sPath) and not fs.isDir(sPath) then
          local fnFile, sError = loadfile(sPath, tEnv)
          if fnFile then
            return fnFile, sPath
          else
            return nil, sError
          end
        else
          if #sError > 0 then
            sError = sError .. "\n  "
          end
          sError = sError .. "no file '" .. sPath .. "'"
        end
      end
      return nil, sError
    end
  }

  local sentinel = {}
  local function require(name)
    if type(name) ~= "string" then
      error("bad argument #1 (expected string, got " .. type(name) .. ")", 2)
    end
    if package.loaded[name] == sentinel then
      error("loop or previous error loading module '" .. name .. "'", 0)
    end
    if package.loaded[name] then
      return package.loaded[name]
    end

    local sError = "module '" .. name .. "' not found:"
    for _, searcher in ipairs(package.loaders) do
      local loader = table.pack(searcher(name))
      if loader[1] then
        package.loaded[name] = sentinel
        local result = loader[1](name, table.unpack(loader, 2, loader.n))
        if result == nil then result = true end

        package.loaded[name] = result
        return result
      else
        sError = sError .. "\n  " .. loader[2]
      end
    end
    error(sError, 2)
  end

  tEnv["package"] = package
  tEnv["require"] = require

  return tEnv
end

-- Colours
local promptColour, textColour, bgColour
if term.isColour() then
  promptColour = colours.yellow
  textColour = colours.white
  bgColour = colours.black
else
  promptColour = colours.white
  textColour = colours.white
  bgColour = colours.black
end

local function run(_sCommand, ...)
  local sPath = shell.resolveProgram(_sCommand)
  if sPath ~= nil then
    tProgramStack[#tProgramStack + 1] = sPath
    if multishell then
      local sTitle = fs.getName(sPath)
      if sTitle:sub(-4) == ".lua" then
        sTitle = sTitle:sub(1,-5)
      end
      multishell.setTitle(multishell.getCurrent(), sTitle)
    end
    local sDir = fs.getDir(sPath)
    local tEnv = setmetatable(createShellEnv(sDir), { __index = _G })

    if settings.get("mbs.shell.strict_globals", false)  then
      tEnv._ENV = tEnv -- load (in bios.lua) will attempt to set _ENV on our environment, which throws an error with this protection enabled. Thus we set it here first.
      getmetatable(tEnv).__newindex = function(_, name, value)
        error("Attempt to create global " .. tostring(name) .. "\n If this is intended then you probably want to use _G." .. tostring(name), 2)
      end
    end

    local ok
    local fnFile, err = loadfile(sPath, tEnv)
    if fnFile then
      if settings.get("mbs.shell.traceback", true) then
        local tArgs = table.pack(...)
        ok, err = stack_trace.xpcall_with(function() return fnFile(table.unpack(tArgs, 1, tArgs.n)) end)
      else
        ok, err = pcall(fnFile, ...)
      end

      if not ok then
        ok = false
        if err and err ~= "" then printError(err) end
      end
    else
      ok = false
      if err and err ~= "" then printError(err) end
    end

    tProgramStack[#tProgramStack] = nil
    if multishell then
      if #tProgramStack > 0 then
        local sTitle = fs.getName(tProgramStack[#tProgramStack])
        if sTitle:sub(-4) == ".lua" then
          sTitle = sTitle:sub(1,-5)
        end
        multishell.setTitle(multishell.getCurrent(), sTitle)
      else
        multishell.setTitle(multishell.getCurrent(), "shell")
      end
    end
    return ok
  else
    printError("No such program")
    return false
  end
end

local function tokenise(...)
  local sLine = table.concat({ ... }, " ")
  local tWords = {}
  local bQuoted = false
  for match in string.gmatch(sLine .. "\"", "(.-)\"") do
    if bQuoted then
      table.insert(tWords, match)
    else
      for m in string.gmatch(match, "[^ \t]+") do
        table.insert(tWords, m)
      end
    end
    bQuoted = not bQuoted
  end
  return tWords
end

-- Install shell API
function shell.run(...)
  local tWords = tokenise(...)
  local sCommand = tWords[1]
  if sCommand then
    return run(sCommand, table.unpack(tWords, 2))
  end
  return false
end

function shell.exit()
  bExit = true
end

function shell.dir()
  return sDir
end

function shell.setDir(_sDir)
  if type(_sDir) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sDir) .. ")", 2)
  end
  if not fs.isDir(_sDir) then
    error("Not a directory", 2)
  end
  sDir = _sDir
end

function shell.path()
  return sPath
end

function shell.setPath(_sPath)
  if type(_sPath) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sPath) .. ")", 2)
  end
  sPath = _sPath
end

function shell.resolve(_sPath)
  if type(_sPath) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sPath) .. ")", 2)
  end
  local sStartChar = string.sub(_sPath, 1, 1)
  if sStartChar == "/" or sStartChar == "\\" then
    return fs.combine("", _sPath)
  else
    return fs.combine(sDir, _sPath)
  end
end

local function pathWithExtension(_sPath, _sExt)
  local nLen = #sPath
  local sEndChar = string.sub(_sPath, nLen, nLen)
  -- Remove any trailing slashes so we can add an extension to the path safely
  if sEndChar == "/" or sEndChar == "\\" then
    _sPath = string.sub(_sPath, 1, nLen - 1)
  end
  return _sPath .. "." .. _sExt
end

function shell.resolveProgram(_sCommand)
  if type(_sCommand) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sCommand) .. ")", 2)
  end
  -- Substitute aliases firsts
  if tAliases[_sCommand] ~= nil then
    _sCommand = tAliases[_sCommand]
  end

  -- If the path is a global path, use it directly
  local sStartChar = string.sub(_sCommand, 1, 1)
  if _sCommand:find("/") or _sCommand:find("\\") then
    local sPath = shell.resolve(_sCommand)
    if fs.exists(sPath) and not fs.isDir(sPath) then
      return sPath
    else
      local sPathLua = pathWithExtension(sPath, "lua")
      if fs.exists(sPathLua) and not fs.isDir(sPathLua) then
        return sPathLua
      end
    end
    return nil
  end

  -- Otherwise, look on the path variable
  for sPath in string.gmatch(sPath, "[^:]+") do
    sPath = fs.combine(shell.resolve(sPath), _sCommand)
    if fs.exists(sPath) and not fs.isDir(sPath) then
      return sPath
    else
      local sPathLua = pathWithExtension(sPath, "lua")
      if fs.exists(sPathLua) and not fs.isDir(sPathLua) then
        return sPathLua
      end
    end
  end

  -- Not found
  return nil
end

function shell.programs(_bIncludeHidden)
  local tItems = {}

  -- Add programs from the path
  for sPath in string.gmatch(sPath, "[^:]+") do
    sPath = shell.resolve(sPath)
    if fs.isDir(sPath) then
      local tList = fs.list(sPath)
      for n=1,#tList do
        local sFile = tList[n]
        if not fs.isDir(fs.combine(sPath, sFile)) and
        (_bIncludeHidden or string.sub(sFile, 1, 1) ~= ".") then
          if #sFile > 4 and sFile:sub(-4) == ".lua" then
            sFile = sFile:sub(1,-5)
          end
          tItems[sFile] = true
        end
      end
    end
  end

  -- Sort and return
  local tItemList = {}
  for sItem in pairs(tItems) do
    table.insert(tItemList, sItem)
  end
  table.sort(tItemList)
  return tItemList
end

local function completeProgram(sLine)
  if #sLine > 0 and (sLine:find("/") or sLine:find("\\")) then
    -- Add programs from the root
    return fs.complete(sLine, sDir, true, false)

  else
    local tResults = {}
    local tSeen = {}

    -- Add aliases
    for sAlias in pairs(tAliases) do
      if #sAlias > #sLine and string.sub(sAlias, 1, #sLine) == sLine then
        local sResult = string.sub(sAlias, #sLine + 1)
        if not tSeen[sResult] then
          table.insert(tResults, sResult)
          tSeen[sResult] = true
        end
      end
    end

    -- Add all subdirectories. We don't include files as they will be added in the block below
    local tDirs = fs.complete(sLine, sDir, false, false)
    for i = 1, #tDirs do
      local sResult = tDirs[i]
      if not tSeen[sResult] then
        table.insert(tResults, sResult)
        tSeen[sResult] = true
      end
    end

    -- Add programs from the path
    local tPrograms = shell.programs()
    for n=1,#tPrograms do
      local sProgram = tPrograms[n]
      if #sProgram > #sLine and string.sub(sProgram, 1, #sLine) == sLine then
        local sResult = string.sub(sProgram, #sLine + 1)
        if not tSeen[sResult] then
          table.insert(tResults, sResult)
          tSeen[sResult] = true
        end
      end
    end

    -- Sort and return
    table.sort(tResults)
    return tResults
  end
end

local function completeProgramArgument(sProgram, nArgument, sPart, tPreviousParts)
  local tInfo = tCompletionInfo[sProgram]
  if tInfo then
    return tInfo.fnComplete(shell, nArgument, sPart, tPreviousParts)
  end
  return nil
end

function shell.complete(sLine)
  if type(sLine) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(sLine) .. ")", 2)
  end
  if #sLine > 0 then
    local tWords = tokenise(sLine)
    local nIndex = #tWords
    if string.sub(sLine, #sLine, #sLine) == " " then
      nIndex = nIndex + 1
    end
    if nIndex == 1 then
      local sBit = tWords[1] or ""
      local sPath = shell.resolveProgram(sBit)
      if tCompletionInfo[sPath] then
        return { " " }
      else
        local tResults = completeProgram(sBit)
        for n=1,#tResults do
          local sResult = tResults[n]
          local sPath = shell.resolveProgram(sBit .. sResult)
          if tCompletionInfo[sPath] then
            tResults[n] = sResult .. " "
          end
        end
        return tResults
      end

    elseif nIndex > 1 then
      local sPath = shell.resolveProgram(tWords[1])
      local sPart = tWords[nIndex] or ""
      local tPreviousParts = tWords
      tPreviousParts[nIndex] = nil
      return completeProgramArgument(sPath , nIndex - 1, sPart, tPreviousParts)

    end
  end
  return nil
end

function shell.completeProgram(sProgram)
  if type(sProgram) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(sProgram) .. ")", 2)
  end
  return completeProgram(sProgram)
end

function shell.setCompletionFunction(sProgram, fnComplete)
  if type(sProgram) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(sProgram) .. ")", 2)
  end
  if type(fnComplete) ~= "function" then
    error("bad argument #2 (expected function, got " .. type(fnComplete) .. ")", 2)
  end
  tCompletionInfo[sProgram] = {
    fnComplete = fnComplete
  }
end

function shell.getCompletionInfo()
  return tCompletionInfo
end

function shell.getRunningProgram()
  if #tProgramStack > 0 then
    return tProgramStack[#tProgramStack]
  end
  return nil
end

function shell.setAlias(_sCommand, _sProgram)
  if type(_sCommand) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sCommand) .. ")", 2)
  end
  if type(_sProgram) ~= "string" then
    error("bad argument #2 (expected string, got " .. type(_sProgram) .. ")", 2)
  end
  tAliases[_sCommand] = _sProgram
end

function shell.clearAlias(_sCommand)
  if type(_sCommand) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sCommand) .. ")", 2)
  end
  tAliases[_sCommand] = nil
end

function shell.aliases()
  -- Copy aliases
  local tCopy = {}
  for sAlias, sCommand in pairs(tAliases) do
    tCopy[sAlias] = sCommand
  end
  return tCopy
end

function shell.history()
  -- Read commands and execute them
  if not history then
    history = {}

    local history_file = settings.get("mbs.shell.history_file", ".shell_history")
    if history_file and fs.exists(history_file) then
      local handle = fs.open(history_file, "r")
      if handle then
        for line in handle.readLine do history[#history + 1] = line end
        handle.close()
      end
    end
  end

  return history
end

if multishell then
  function shell.openTab(...)
    local tWords = tokenise(...)
    local sCommand = tWords[1]
    if sCommand then
      local sPath = shell.resolveProgram(sCommand)
      if sPath == "rom/programs/shell.lua" then
        return multishell.launch(createShellEnv("rom/programs"), sPath, table.unpack(tWords, 2))
      elseif sPath ~= nil then
        return multishell.launch(createShellEnv("rom/programs"), "rom/programs/shell.lua", sCommand, table.unpack(tWords, 2))
      else
        printError("No such program")
      end
    end
  end

  function shell.switchTab(nID)
    if type(nID) ~= "number" then
      error("bad argument #1 (expected number, got " .. type(nID) .. ")", 2)
    end
    multishell.setFocus(nID)
  end
end

local tArgs = { ... }
if #tArgs > 0 then
  -- "shell x y z": Run the program specified on the commandline
  shell.run(...)
  return
end

-- "shell": Run the shell REPL
local parent = term.current()
local redirect = scroll_window.create(parent)

local function get_first_startup()
  if fs.exists("startup.lua") then return "startup.lua" end
  if fs.isDir("startup")  then
    local first = fs.list("startup")[1]
    if first then return fs.combine("startup", first) end
  end

  return nil
end

--- Create a wrapper for various read functions, allowing the user to scroll
-- when typing.
local scroll_offset = nil
fWrapper = function(fn)
  return function(...)
    -- Set the scroll_offset to 0 to allow scrolling
    scroll_offset = 0

    local ok, res = pcall(fn, ...)

    -- And set to nil again to disable
    if scroll_offset ~= 0 then redirect.draw(0) end
    scroll_offset = nil

    if not ok then error(res, 0) end
    return res
  end
end

local worker = coroutine.create(function()

  -- Print the header
  term.redirect(redirect)
  term.setCursorPos(1, 1)
  term.setBackgroundColor(bgColour)
  term.setTextColour(promptColour)
  print(os.version() .. " (+MBS)")
  term.setTextColour(textColour)

  if parentShell == nil then
    -- If we've no parent shell. run the startup script. It's pretty unlikely,
    -- but some mad people might be using it!
    shell.run("/rom/startup.lua")
  elseif parentShell.getRunningProgram() == get_first_startup() then
    -- If we're currently in the first startup file, then run all the others.
    local current = parentShell.getRunningProgram()

    -- Run /startup or /startup.lua
    local root_startup = shell.resolveProgram("startup")
    if root_startup and root_startup ~= current then shell.run("/" .. root_startup) end

    -- Run startup/*
    if fs.isDir("startup") then
      for _, file in ipairs(fs.list("startup")) do
        local sub_startup = fs.combine("startup", file)
        if sub_startup ~= current and not fs.isDir(sub_startup) then
          shell.run("/" .. sub_startup)
        end
      end
    end
  end

  -- The main interaction loop
  local history = shell.history()
  local wrapped_read = fWrapper(read)
  while not bExit do
    local scrollback = tonumber(settings.get("mbs.shell.scroll_max", 1e3))
    if scrollback then redirect.setMaxScrollback(scrollback) end

    term.setBackgroundColor(bgColour)
    term.setTextColour(promptColour)
    if term.getCursorPos() ~= 1 then print() end
    write(shell.dir() .. "> ")
    term.setTextColour(textColour)

    local line
    if settings.get("shell.autocomplete") then
      line = wrapped_read(nil, history, shell.complete)
    else
      line = wrapped_read(nil, history)
    end

    if not line then break end

    if line:match("%S") and history[#history] ~= line then
      -- Add item to history
      history[#history + 1] = line

      -- Remove extra items from history
      local max = tonumber(settings.get("mbs.shell.history_max", 1e4)) or 1e4
      while #history > max do table.remove(history, 1) end

      -- Write history file
      local history_file = settings.get("mbs.shell.history_file", ".shell_history")
      if history_file then
        local handle = fs.open(history_file, "w")
        if handle then
          for i = 1, #history do handle.writeLine(history[i]) end
          handle.close()
        end
      end
    end

    local _, y = term.getCursorPos()
    redirect.setCursorThreshold(y)

    local ok = shell.run(line)

    term.redirect(redirect)
    redirect.endPrivateMode(not ok)
    redirect.draw(0)
  end

  term.redirect(parent)
end)

local ok, filter = coroutine.resume(worker)

-- We run the main worker inside a coroutine, catching any potential scroll
-- events.
while coroutine.status(worker) ~= "dead" do
  local event = table.pack(coroutine.yield())
  local e = event[1]

  -- Run the main REPL worker
  if filter == nil or e == filter or e == "terminate" then
    ok, filter = coroutine.resume(worker, table.unpack(event, 1, event.n))
  end

  -- Resize the terminal if required
  if e == "term_resize" then
    redirect.updateSize()
    redirect.draw(scroll_offset or 0, true)
  end

  -- If we're in some interactive function, allow scrolling the input
  if scroll_offset then
    local change = 0
    if e == "mouse_scroll" then
      change = event[2]
    elseif e == "key" and event[2] == keys.pageDown then
      change = 10
    elseif e == "key" and event[2] == keys.pageUp then
      change = -10
    elseif e == "key" or e == "paste" then
      -- Reset offset if another key is pressed
      change = -scroll_offset
    end

    if change ~= 0 and term.current() == redirect and not redirect.isPrivateMode() then
      scroll_offset = scroll_offset + change
      if scroll_offset > 0 then scroll_offset = 0 end
      if scroll_offset < -redirect.getTotalHeight() then scroll_offset = -redirect.getTotalHeight() end
      redirect.draw(scroll_offset)
    end
  end
end

if not ok then error(filter, 0) end
