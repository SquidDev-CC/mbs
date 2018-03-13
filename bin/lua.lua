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

local function serialize_impl(t, tracking, indent, tuple_length)
  local obj_type = type(t)
  if obj_type == "table" and not tracking[t] then
    tracking[t] = true

    if next(t) == nil then
      if tuple_length then
        return "()"
      else
        return "{}"
      end
    else
      local should_newline = false
      local length = tuple_length or #t

      local builder = 0
      for k, v in pairs(t) do
        if type(k) == "table" or type(v) == "table" then
          should_newline = true
          break
        elseif type(k) == "number" and k >= 1 and k <= length and k % 1 == 0 then
          builder = builder + #tostring(v) + 2
        else
          builder = builder + #tostring(v) + #tostring(k) + 2
        end

        if builder > 30 then
          should_newline = true
          break
        end
      end

      local newline, next_newline, sub_indent = "", ", ", ""
      if should_newline then
        newline = "\n"
        next_newline = ",\n"
        sub_indent = indent .. " "
      end

      local result, n = {(tuple_length and "(" or "{") .. newline}, 1

      local seen = {}
      local first = true
      for k = 1, length do
        seen[k] = true
        n = n + 1
        local entry = sub_indent .. serialize_impl(t[k], tracking, sub_indent)

        if not first then
          entry = next_newline .. entry
        else
          first = false
        end

        result[n] = entry
      end

      for k,v in pairs(t) do
        if not seen[k] then
          local entry
          if type(k) == "string" and not keywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
            entry = k .. " = " .. serialize_impl(v, tracking, sub_indent)
          else
            entry = "[" .. serialize_impl(k, tracking, sub_indent) .. "] = " .. serialize_impl(v, tracking, sub_indent)
          end

          entry = sub_indent .. entry

          if not first then
            entry = next_newline .. entry
          else
            first = false
          end

          n = n + 1
          result[n] = entry
        end
      end

      n = n + 1
      result[n] = newline .. indent .. (tuple_length and ")" or "}")
      return table.concat(result)
    end

  elseif obj_type == "string" then
    return (string.format("%q", t):gsub("\\\n", "\\n"))
  else
    return tostring(t)
  end
end

local function serialise(t, n)
  return serialize_impl(t, {}, "", n)
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
    local meta = getmetatable(out)
    if type(meta) == "table" and type(meta.__tostring) == "function" then
      print(tostring(out))
    else
      print(serialise(out, length))
    end
  else
    print(serialise(out))
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
      handle(force_print, pcall(func))
    else
      printError(e)
    end

    counter = counter + 1
  end
end
