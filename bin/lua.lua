if select('#', ...) > 0 then
  print("This is an interactive Lua prompt.")
  print("To run a lua program, just type its name.")
  return
end

local keywords = {
  [ "and" ] = true, [ "break" ] = true, [ "do" ] = true, [ "else" ] = true,
  [ "elseif" ] = true, [ "end" ] = true, [ "false" ] = true, [ "for" ] = true,
  [ "function" ] = true, [ "if" ] = true, [ "in" ] = true, [ "local" ] = true,
  [ "nil" ] = true, [ "not" ] = true, [ "or" ] = true, [ "repeat" ] = true, [ "return" ] = true,
  [ "then" ] = true, [ "true" ] = true, [ "until" ] = true, [ "while" ] = true,
}

local function write_with(colour, text)
  term.setTextColour(colour)
  write(text)
end

local function pretty_sort(a, b)
  local ta, tb = type(a), type(b)

  if ta == "string" then return tb ~= "string" or a < b
  elseif tb == "string" then return false
  end

  if ta == "number" then return tb ~= "number" or a < b end
  return false
end

local debug_info = type(debug) == "table" and type(debug.getinfo) == "function" and debug.getinfo
local function pretty_function(fn)
  if debug_info then
    local info = debug_info(fn, "S")
    if info.short_src and info.linedefined and info.linedefined >= 1 then
      return "function<" .. info.short_src .. ":" .. info.linedefined .. ">"
    end
  end

  return tostring(fn)
end

local function pretty_size(obj, tracking, limit)
  local obj_type = type(obj)
  if obj_type == "string" then return #string.format("%q", obj):gsub("\\\n", "\\n")
  elseif obj_type == "function" then return #pretty_function(obj)
  elseif obj_type ~= "table" or tracking[obj] then return #tostring(obj) end

  local count = 2
  tracking[obj] = true
  for k, v in pairs(obj) do
    count = count + pretty_size(k, tracking, limit) + pretty_size(v, tracking, limit)
    if count >= limit then break end
  end
  tracking[obj] = nil
  return count
end

local function pretty_impl(obj, tracking, width, height, indent, tuple_length)
  local obj_type = type(obj)
  if obj_type == "string" then
    local formatted = string.format("%q", obj):gsub("\\\n", "\\n")

    -- Strings are limited to the size of the current buffer with a bit of padding
    local limit = math.max(8, math.floor(width * height * 0.8))
    if #formatted > limit then
      write_with(colours.red, formatted:sub(1, limit - 3))
      write_with(colours.grey, "...")
    else
      write_with(colours.red, formatted)
    end
    return
  elseif obj_type == "number" then
    return write_with(colours.magenta, tostring(obj))
  elseif obj_type == "function" then
    return write_with(colours.lightGrey, pretty_function(obj))
  elseif obj_type ~= "table" or tracking[obj] then
    return write_with(colours.lightGrey, tostring(obj))
  elseif (getmetatable(obj) or {}).__tostring then
    return write_with(colours.white, tostring(obj))
  end

  local open, close = "{", "}"
  if tuple_length then open, close = "(", ")" end

  if (tuple_length == nil or tuple_length == 0) and next(obj) == nil then
    return write_with(colours.white, open .. close)
  elseif width <= 7 then
    write_with(colours.white, open) write_with(colours.grey, " ... ") write_with(colours.white, close)
    return
  end

  local should_newline = false
  local length = tuple_length or #obj

  -- Compute the "size" of this object and how many children it has.
  local size, children, keys, kn = 2, 0, {}, 0
  for k, v in pairs(obj) do
    if type(k) == "number" and k >= 1 and k <= length and k % 1 == 0 then
      local vs = pretty_size(v, tracking, width)
      size = size + vs + 2
      children = children + 1
    else
      kn = kn + 1
      keys[kn] = k

      local vs, ks = pretty_size(v, tracking, width), pretty_size(k, tracking, width)
      size = size + vs + ks + 2
      children = children + 2
    end

    -- Some aribtrary scale factor to stop long lines filling too much of the
    -- screen
    if size >= width * 0.6 then should_newline = true end
  end

  -- If we want to have multiple lines, but don't fit in one then abort!
  if should_newline and height <= 1 then
    write_with(colours.white, open) write_with(colours.grey, " ... ") write_with(colours.white, close)
    return
  end

  -- Make sure our keys are in some sort of sensible order
  table.sort(keys, pretty_sort)

  local next_newline, sub_indent, child_width, child_height
  if should_newline then
    next_newline, sub_indent = ",\n", indent .. " "

    -- We split our height over multiple items. A future improvement could be to
    -- give more "height" to complex elements (such as tables)
    height = height - 2
    child_width, child_height = width - 2, math.ceil(height / children)

    -- If there's more children then we have space then
    if children > height then children = height - 2 end
  else
    next_newline, sub_indent =  ", ", ""

    -- Like multi-line elements, we share the width across multiple children
    width = width - 2
    child_width, child_height = math.ceil(width / children), 1
  end

  write_with(colours.white, open .. (should_newline and "\n" or " "))

  tracking[obj] = true
  local seen = {}
  local first = true
  for k = 1, length do
    if not first then write_with(colours.white, next_newline) else first = false end
    write_with(colours.white, sub_indent)

    seen[k] = true
    pretty_impl(obj[k], tracking, child_width, child_height, sub_indent)

    children = children - 1
    if children < 0 then
      if not first then write_with(colours.white, next_newline) else first = false end
      write_with(colours.grey, sub_indent .. "...")
      break
    end
  end

  for i = 1, kn do
    local k, v = keys[i], obj[keys[i]]
    if not seen[k] then
      if not first then write_with(colours.white, next_newline) else first = false end
      write_with(colours.white, sub_indent)

      if type(k) == "string" and not keywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
        write_with(colours.white, k .. " = ")
        pretty_impl(v, tracking, child_width, child_height, sub_indent)
      else
        write_with(colours.white, "[")
        pretty_impl(k, tracking, child_width, child_height, sub_indent)
        write_with(colours.white, "] = ")
        pretty_impl(v, tracking, child_width, child_height, sub_indent)
      end

      children = children - 1
      if children < 0 then
        if not first then write_with(colours.white, next_newline) else first = false end
        write_with(colours.grey, sub_indent .. "...")
        break
      end
    end
  end
  tracking[obj] = nil

  write_with(colours.white, (should_newline and "\n" .. indent or " ") .. (tuple_length and ")" or "}"))
end

local function pretty(t, n)
  local width, height = term.getSize()
  return pretty_impl(t, {}, width, height - 2, "", n)
end

local running = true
local history = {}
local counter = 1
local output = {}

local environment = setmetatable({
  exit = setmetatable({}, {
    __tostring = function() return "Call exit() to exit" end,
    __call = function() running = false end,
  }),

  _noTail = function(...) return ... end,

  out = output,
}, { __index = _ENV })

local input_colour, output_colour, text_colour = colours.green, colours.cyan, term.getTextColour()
if not term.isColour() then
  input_colour, output_colour = colours.white, colours.white
end

local autocomplete = nil
if not settings or settings.get("lua.autocomplete") then
  autocomplete = function(line)
    local start = line:find("[a-zA-Z0-9_%.:]+$")
    if start then
      line = line:sub(start)
    end
    if #line > 0 then
      return textutils.complete(line, environment)
    end
  end
end

local history_file = settings.get("mbs.lua.history_file", ".lua_history")
if history_file and fs.exists(history_file) then
  local handle = fs.open(history_file, "r")
  if handle then
    for line in handle.readLine do history[#history + 1] = line end
    handle.close()
  end
end

local function set_output(out, length)
  environment._ = out
  environment['_' .. counter] = out
  output[counter] = out

  term.setTextColour(output_colour)
  write("out[" .. counter .. "]: ")
  term.setTextColour(text_colour)

  if type(out) == "table" then
    print(pretty(out, length))
  else
    print(pretty(out))
  end
end

--- Handle the result of the function
local function handle(force_print, success, ...)
  if success then
    local len = select('#', ...)
    if len == 0 then
      if force_print then
        set_output(nil)
      end
    elseif len == 1 then
      set_output(...)
    else
      set_output({...}, len)
    end
  else
    printError(...)
  end
end

if type(package) == "table" and type(package.path) == "string" then
  -- Attempt to determine the shell directory with leading and trailing slashes
  local dir = shell.dir()
  if dir:sub(1, 1) ~= "/" then dir = "/" .. dir end
  if dir:sub(#dir, #dir) ~= "/" then dir = dir .. "/" end

  -- Strip the default "current program" package path
  local strip_path = "?;?.lua;?/init.lua;"
  local path = package.path
  if path:sub(1, #strip_path) == strip_path then path = path:sub(#strip_path + 1) end

  -- And append the current directory to the package path
  package.path = dir .. "?;" .. dir .. "?.lua;" .. dir .. "?/init.lua;" .. path
end

while running do
  term.setTextColour(input_colour)
  term.write("in [" .. counter .. "]: ")
  term.setTextColour(text_colour)

  local line = read(nil, history, autocomplete)
  if not line then break end

  if line:find("%S") then
    if line ~= history[#history] then
      -- Add item to history
      history[#history + 1] = line

      -- Remove extra items from history
      local max = tonumber(settings.get("mbs.lua.history_max", 1e4)) or 1e4
      while #history > max do table.remove(history, 1) end

      -- Write history file
      local history_file = settings.get("mbs.lua.history_file", ".lua_history")
      if history_file then
        local handle = fs.open(history_file, "w")
        if handle then
          for i = 1, #history do handle.writeLine(history[i]) end
          handle.close()
        end
      end
    end

    local force_print = true
    local func, e = load("return " .. line, "=lua", "t", environment)
    if not func then
      func, e = load(line, "=lua", "t", environment)
      force_print = false
    else
      func, e = load("return _noTail(" .. line .. ")", "=lua", "t", environment)
    end

    if func then
      if settings.get("mbs.lua.traceback", true) then
        handle(force_print, stack_trace.xpcall_with(func))
      else
        handle(force_print, pcall(func))
      end
    else
      printError(e)
    end

    counter = counter + 1
  end
end
