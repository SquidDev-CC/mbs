if select('#', ...) > 0 then
  print("This is an interactive Lua prompt.")
  print("To run a lua program, just type its name.")
  return
end

local input_colour,  output_colour, text_colour,          keyword_colour, comment_colour, string_colour =
      colours.green, colours.cyan,  term.getTextColour(), colours.yellow, colours.grey,   colours.red
local number_colour,   extra_colour, object_colour =
      colours.magenta, colours.grey, colours.lightGrey

local keywords = {
  ["and"] = keyword_colour, ["break"] = keyword_colour, ["do"] = keyword_colour,
  ["else"] = keyword_colour, ["elseif"] = keyword_colour, ["end"] = keyword_colour,
  ["false"] = object_colour, ["for"] = keyword_colour, ["function"] = keyword_colour,
  ["if"] = keyword_colour, ["in"] = keyword_colour, ["local"] = keyword_colour,
  ["nil"] = object_colour, ["not"] = keyword_colour, ["or"] = keyword_colour,
  ["repeat"] = keyword_colour, ["return"] = keyword_colour, ["then"] = keyword_colour,
  ["true"] = object_colour, ["until"] = keyword_colour, ["while"] = keyword_colour,
}

local tokens = {
  { "^%s+", text_colour },

  -- Identifiers and keywords
  { "^[%a_][%w_]*", function(match) return keywords[match] or text_colour end },

  -- TODO: Exponents + hex, partial strings and comments

  { "^%-%-%[%[.-%]%]", comment_colour },
  { "^%-%-.*",         comment_colour },

  { [[^".-[^\]"]], string_colour }, -- Complete strings
  { [[^"[^"]*"?]], string_colour }, -- Incomplete strings
  { [[^'.-[^\]']], string_colour }, -- Complete strings
  { [[^'[^"]*'?]], string_colour }, -- Incomplete strings
  { "^%[%[.-%]%]", string_colour },

  { "^0x[a-fA-F0-9]*", number_colour }, -- Hexadecimal

  { "^%d+%.%d*e[-+]?%d*", number_colour }, -- 23.4e+2
  { "^%d+%.%d*", number_colour },          -- 23.2
  { "^%d+e[-+]?%d*", number_colour },      -- 23e+2
  { "^%d+", number_colour },               -- 23

  { "^%.%d*e[-+]?%d*", number_colour },    -- .23e+2
  { "^%.%d*", number_colour },             -- .23

  { "^[^%w_]", text_colour }, -- Consume some unknown input
}

--- A basic highlighting function:
local function highlight(line, start)
  local find, type = string.find, type
  for i = 1, #tokens do
    local token = tokens[i]
    local pat_start, pat_finish = find(line, token[1], start)
    if pat_finish then
      if type(token[2]) == "function" then
        return pat_finish, token[2](line:sub(pat_start, pat_finish))
      else
        return pat_finish, token[2]
      end
    end
  end

  return #line, text_colour
end

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
local debug_local = type(debug) == "table" and type(debug.getlocal) == "function" and debug.getlocal
local function pretty_function(fn)
  local info = debug_info and debug_info(fn, "Su")

  -- Include function source position if available
  local name
  if info and info.short_src and info.linedefined and info.linedefined >= 1 then
    name = "function<" .. info.short_src .. ":" .. info.linedefined .. ">"
  else
    name = tostring(fn)
  end

  -- Include arguments if a Lua function and if available. Lua will report "C"
  -- functions as variadic.
  if info and info.what == "Lua" and info.nparams and debug_local then
    local args = {}
    for i = 1, info.nparams do args[i] = debug_local(fn, i) or "?" end
    if info.isvararg then args[#args + 1] = "..." end
    name = name .. "(" .. table.concat(args, ", ") .. ")"
  end

  return name
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
      write_with(string_colour, formatted:sub(1, limit - 3))
      write_with(extra_colour, "...")
    else
      write_with(string_colour, formatted)
    end
    return
  elseif obj_type == "number" then
    return write_with(number_colour, tostring(obj))
  elseif obj_type == "function" then
    return write_with(object_colour, pretty_function(obj))
  elseif obj_type ~= "table" or tracking[obj] then
    return write_with(object_colour, tostring(obj))
  elseif (getmetatable(obj) or {}).__tostring then
    return write_with(text_colour, tostring(obj))
  end

  local open, close = "{", "}"
  if tuple_length then open, close = "(", ")" end

  if (tuple_length == nil or tuple_length == 0) and next(obj) == nil then
    return write_with(text_colour, open .. close)
  elseif width <= 7 then
    write_with(text_colour, open) write_with(extra_colour, " ... ") write_with(text_colour, close)
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
    write_with(text_colour, open) write_with(extra_colour, " ... ") write_with(text_colour, close)
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

  write_with(text_colour, open .. (should_newline and "\n" or " "))

  tracking[obj] = true
  local seen = {}
  local first = true
  for k = 1, length do
    if not first then write_with(text_colour, next_newline) else first = false end
    write_with(text_colour, sub_indent)

    seen[k] = true
    pretty_impl(obj[k], tracking, child_width, child_height, sub_indent)

    children = children - 1
    if children < 0 then
      if not first then write_with(text_colour, next_newline) else first = false end
      write_with(extra_colour, sub_indent .. "...")
      break
    end
  end

  for i = 1, kn do
    local k, v = keys[i], obj[keys[i]]
    if not seen[k] then
      if not first then write_with(text_colour, next_newline) else first = false end
      write_with(text_colour, sub_indent)

      if type(k) == "string" and not keywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
        write_with(text_colour, k .. " = ")
        pretty_impl(v, tracking, child_width, child_height, sub_indent)
      else
        write_with(text_colour, "[")
        pretty_impl(k, tracking, child_width, child_height, sub_indent)
        write_with(text_colour, "] = ")
        pretty_impl(v, tracking, child_width, child_height, sub_indent)
      end

      children = children - 1
      if children < 0 then
        if not first then write_with(text_colour, next_newline) else first = false end
        write_with(extra_colour, sub_indent .. "...")
        break
      end
    end
  end
  tracking[obj] = nil

  write_with(text_colour, (should_newline and "\n" .. indent or " ") .. (tuple_length and ")" or "}"))
end

local function pretty(t, n)
  local width, height = term.getSize()
  local fit_height = settings.get("mbs.lua.pretty_height", true)
  if type(fit_height) == "number" then height = fit_height
  elseif fit_height == false then height = 1 / 0 end
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

-- Replace require/package with a new instance that loads from the current
-- directory.
environment.require, environment.package = require "cc.require".make(environment, shell.dir())

local function process_auto_run_file(folderPath, file)
  if string.sub( file, 1, 1 ) == "." then return end

  local path = fs.combine(folderPath, file)
  if fs.isDir( path ) then return end

  local func, err = loadfile(path, nil, _ENV)
  if not func then
    printError(err)
    return
  end

  local ok, result
  if settings.get("mbs.lua.traceback", true) then
    ok, result = stack_trace.xpcall_with(func)
  else
    ok, result = pcall(func)
  end
  if not ok then
    printError(result)
  end
end

local function load_auto_run_folder(folderPath)
  if fs.exists( folderPath ) and fs.isDir( folderPath ) then
    local files = fs.list( folderPath )
    for _, file in ipairs( files ) do
      process_auto_run_file(folderPath, file)
    end
  end
end

load_auto_run_folder("/rom/lua_autorun")
load_auto_run_folder("/lua_autorun")

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
local function handle(success, ...)
  if success then
    local len = select('#', ...)
    if len == 0 then
      -- Do nothing
    elseif len == 1 then
      set_output(...)
    else
      set_output({...}, len)
    end
  else
    printError(...)
  end
end


while running do
  term.setTextColour(input_colour)
  term.write("in [" .. counter .. "]: ")
  term.setTextColour(text_colour)

  local line
  if readline and readline.read and settings.get("mbs.lua.highlight") then
    line = readline.read {
      history = history,
      complete = autocomplete,
      highlight = highlight,
    }
  else
    line = read(nil, history, autocomplete)
  end
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

    local func, err = load(line, "=lua", "t", environment)
    if load("return " .. line) then
        func = load("return _noTail(" .. line .. "\n)", "=lua", "t", environment)
    end

    if func then
      if settings.get("mbs.lua.traceback", true) then
        handle(stack_trace.xpcall_with(func))
      else
        handle(pcall(func))
      end
    else
      printError(err)
    end

    counter = counter + 1
  end
end
