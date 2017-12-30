local arg = table.pack(...)
local root_dir = ".mbs"
local repo_url = "https://raw.githubusercontent.com/SquidDev-CC/mbs/master/"

--- Write a string with the given colour to the terminal
local function write_coloured(colour, text)
  local old = term.getTextColour()
  term.setTextColour(colour)
  write(text)
  term.setTextColour(old)
end

--- Print usage for this program
local commands = { "install", "modules", "module" }
local function print_usage()
  local name = fs.getName(shell.getRunningProgram()):gsub("%.lua$", "")
  write_coloured(colours.cyan, name .. " modules ") print("Print the status of all modules")
  write_coloured(colours.cyan, name .. " module  ") print("Print information about a given module")
  write_coloured(colours.cyan, name .. " install ") print("Download all modules and create a startup file")
end

--- Attempt to load a module from the given path, returning the module or false
-- and an error message.
local function load_module(path)
  if fs.isDir(path) then return false, "Invalid module (is directory)" end

  local fn, err = loadfile(path, _ENV)
  if not fn then return false, "Invalid module (" .. err .. ")" end

  local ok, res = pcall(fn)
  if not ok then return false, "Invalid module (" .. res .. ")" end

  if type(res) ~= "table" or type(res.description) ~= "string" or type(res.enabled) ~= "function" then
    return false, "Malformed module"
  end

  return res
end

--- Setup all modules
local function setup_module(module)
  for _, setting in ipairs(module.settings) do
    if settings.get(setting.name) == nil then
      settings.set(setting.name, setting.default)
    end
  end
end

--- Download a set of files
local function download_files(files)
  if #files == 0 then return end

  local urls = {}
  local remaining = #files
  for _, file in ipairs(files) do
    local url = repo_url .. file
    http.request(url)
    urls[url] = file
  end

  while true do
    local event, url, arg1, arg2 = os.pullEvent()
    if event == "http_success" and urls[url] then
      local handle = fs.open(fs.combine(root_dir, urls[url]), "w")
      handle.write(arg1.readAll())
      handle.close()
      arg1.close()

      urls[url] = nil
      if next(urls) == nil then return end
    elseif event == "http_failure" and urls[url] then
      error("Could not download " .. urls[url], 0)
    end
  end

  return true
end

--- read completion helper, completes text using the given options
local function complete_multi(text, options, add_spaces)
  local results = {}
  for n = 1, #options do
    local option = options[n]
    if #option + (add_spaces and 1 or 0) > #text and option:sub(1, #text) == text then
      local result = option:sub(#text + 1)
      if add_spaces then
        results[#results + 1] = result .. " "
      else
        results[#results + 1] = result
      end
    end
  end
  return results
end

if arg.n == 0 then
  printError("Expected some command")
  print_usage()
  error()
elseif arg[1] == "install" then
  -- Load all modules and update them.
  local module_dir = fs.combine(root_dir, "modules")
  local modules = fs.isDir(module_dir) and fs.list(module_dir)
    or { "lua.lua", "readline.lua", "shell.lua" }
  local files = {}
  for i = 1, #modules do files[i] = "modules/" .. modules[i] end
  download_files(files)

  -- Scan for dependencies in enabled modules, downloading them as well
  local deps = {}
  for i = 1, #files do
    local module, err = load_module(fs.combine(root_dir, files[i]))
    if module then
      setup_module(module)
      if module.enabled() then
        for _, dep in ipairs(module.dependencies) do deps[#deps + 1] = dep end
      end
    end
  end
  download_files(deps)

  -- If we're on CC 1.80 then we'll create a startup directory and use that.
  if fs.exists("rom/startup.lua") then
    -- Move the existing startup file if required
    if fs.exists("startup") and not fs.isDir("startup")then
      local handle = fs.open("startup", "r")
      local contents = handle.readAll()
      handle.close()
      fs.delete("startup")

      handle = fs.open("startup/00_init.lua", "w")
      handle.write(contents)
      handle.close()
    end

    -- We'll write at the last posible position
    local handle = fs.open("startup/99_mbs.lua", "w")
    handle.writeLine(("shell.run(%q)"):format(shell.getRunningProgram() .. " startup"))
    handle.close()
  else
    -- Otherwise just append to the startup file

    -- A rather ugly hack to determine if we have an uncommented "mbs startup" somewhere
    -- in the file.
    -- Note this doesn't handle block comments, but it's good enough.
    local contains = false
    local body = ("shell.run(%q)"):format(shell.getRunningProgram() .. " startup")
    if fs.exists("startup") then
      local handle = fs.open("startup", "r")
      contains = ("\n" .. handle.readAll() .. "\n"):find("\n" .. body .. "\n", 1, true)
      handle.close()
    end

    -- If we've no existing "mbs startup" then append it to the end.
    if not contains then
      local handle = fs.open("startup", "a")
      handle.writeLine(body)
      handle.close()
    end
  end

  print("Please reboot to apply changes.")
elseif arg[1] == "startup" then
  -- Gather a list of all modules
  local module_dir = fs.combine(root_dir, "modules")
  local files = fs.isDir(module_dir) and fs.list(module_dir) or {}

  -- Load those modules and determine which are enabled.
  local enabled = {}
  local module_names = {}
  for _, file in ipairs(files) do
    local module = load_module(fs.combine(module_dir, file))
    if module then
      setup_module(module)
      module_names[#module_names + 1] = file:gsub("%.lua$", "")
      if module.enabled() then enabled[#enabled + 1] = module end
    end
  end

  local commands = { "install", "modules", "module" }
  local options = {}
  shell.setCompletionFunction(shell.getRunningProgram(), function(shell, index, text, previous)
    if index == 1 then
      return complete_multi(text, commands, true)
    elseif index == 2 and previous[#previous] == "module" then
      return complete_multi(text, module_names, false)
    end
  end)

  -- Setup those modules
  for _, module in ipairs(enabled) do
    if type(module.setup) == "function" then module.setup(root_dir) end
  end

  -- And run the startup hook if needed
  for _, module in ipairs(enabled) do
    if type(module.startup) == "function" then module.startup(root_dir) end
  end

elseif arg[1] == "modules" then
  local module_dir = fs.combine(root_dir, "modules")
  local files = fs.isDir(module_dir) and fs.list(module_dir) or {}
  local found_any = false

  for _, file in ipairs(files) do
    local res, err = load_module(fs.combine(module_dir, file))
    write_coloured(colours.cyan, file:gsub("%.lua$", "") .. " ")
    if res then
      write(res.description)
      if res.enabled() then
        write_coloured(colours.green, " (enabled)")
      else
        write_coloured(colours.red, " (disabled)")
      end
      found_any = true
    else
      write_coloured(colours.red, err)
    end

    print()
  end

  if not found_any then error("No modules found. Maybe try running the `install` command?", 0) end
elseif arg[1] == "module" then
  if not arg[2] then error("Expected module name", 0) end
  local module, err = load_module(fs.combine(root_dir, fs.combine("modules", arg[2] .. ".lua")))
  if not module then error(err, 0) end

  write(module.description)
  if module.enabled() then
    write_coloured(colours.green, " (enabled)")
  else
    write_coloured(colours.red, " (disabled)")
  end
  print()

  print()

  for _, setting in ipairs(module.settings) do
    local value = settings.get(setting.name)
    write_coloured(colours.cyan, setting.name)
    write(" " .. setting.description .. " (")
    write_coloured(colours.yellow, textutils.serialise(value))
    if value ~= setting.default then
      write(", default is ")
      write_coloured(colours.yellow, textutils.serialise(setting.default))
    end

    write(")")
    print()
  end
else
  printError("Unknown command")
  print_usage()
  error()
end
