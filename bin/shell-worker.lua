local history = {}
do
  local history_file = settings.get("mbs.shell.history_file", ".shell_history")
  if history_file and fs.exists(history_file) then
    local handle = fs.open(history_file, "r")
    if handle then
      for line in handle.readLine do history[#history + 1] = line end
      handle.close()
    end
  end

  local max = tonumber(settings.get("mbs.shell.history_max", 1e4)) or 1e4
  if #history > max then
    while #history > max do table.remove(history, 1) end

    local history_file = settings.get("mbs.shell.history_file", ".shell_history")
    if history_file then
      local handle = fs.open(history_file, "w")
      if handle then
        for i = 1, #history do handle.writeLine(history[i]) end
        handle.close()
      end
    end
  end
end

-- Nasty! Thankfully we don't actually need to worry about this, as
-- we'll always be launched by our shell bootstrap.
shell.exit()
local running = true
function shell.exit() running = false end

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

local parent = term.current()
local redirect = scroll_window.create(parent)

local function get_first_startup()
  if fs.exists("startup.lua") and not fs.isDir("startup.lua") then
    return "startup.lua"
  end
  if fs.isDir("startup")  then
    local first = fs.list("startup")[1]
    if first then return fs.combine("startup", first) end
  end

  return nil
end

local scroll_offset = 0

local worker = coroutine.create(function()
  -- Print the header
  term.redirect(redirect)
  term.setCursorPos(1, 1)
  term.setBackgroundColor(bgColour)
  term.setTextColour(promptColour)
  print(os.version() .. " (+MBS)")
  term.setTextColour(textColour)

  if shell.getRunningProgram() == get_first_startup() then
    -- If we're currently in the first startup file, then run all the others.
    local current = shell.getRunningProgram()

    if settings.get("motd.enable") then shell.run("motd") end

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
  while running do
    local scrollback = tonumber(settings.get("mbs.shell.scroll_max", 1e3))
    if scrollback then redirect.setMaxScrollback(scrollback) end

    term.setBackgroundColor(bgColour)
    term.setTextColour(promptColour)
    if term.getCursorPos() ~= 1 then print() end
    write(shell.dir() .. "> ")
    term.setTextColour(textColour)

    local line
    if settings.get("shell.autocomplete") then
      line = read(nil, history, shell.complete)
    else
      line = read(nil, history)
    end

    if not line then break end

    if line:match("%S") and history[#history] ~= line then
      -- Add item to history
      history[#history + 1] = line

      -- Write history file
      local history_file = settings.get("mbs.shell.history_file", ".shell_history")
      if history_file then
        local handle = fs.open(history_file, "a")
        handle.writeLine(line)
        handle.close()
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
  if redirect.getCursorBlink() then
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
