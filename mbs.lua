local arg = table.pack(...)
local root_dir = settings.get("mbs.install_path", ".mbs")
local rom_dir = "rom/.mbs"
local install_dir = fs.exists(root_dir) and root_dir or rom_dir
local repo_url = "https://raw.githubusercontent.com/SquidDev-CC/mbs/master/"

--- Write a string with the given colour to the terminal
local function write_coloured(colour, text)
  local old = term.getTextColour()
  term.setTextColour(colour)
  io.write(text)
  term.setTextColour(old)
end

--- Print usage for this program
local commands = { "install", "modules", "module", "download" }
local function print_usage()
  local name = fs.getName(shell.getRunningProgram()):gsub("%.lua$", "")
  write_coloured(colours.cyan, name .. " modules  ") io.write("Print the status of all modules\n")
  write_coloured(colours.cyan, name .. " module   ") io.write("Print information about a given module\n")
  write_coloured(colours.cyan, name .. " install  ") io.write("Download all modules and create a startup file\n")
  write_coloured(colours.cyan, name .. " download ") io.write("Download all modules WITHOUT creating a startup file\n")
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
    if settings.define then
      settings.define(setting.name, {
        description = setting.description,
        type = setting.type,
        default = setting.default,
      })
    elseif settings.get(setting.name) == nil then
      settings.set(setting.name, setting.default)
    end
  end
end

--- Download a set of files
local function download_files(files)
  if #files == 0 then return end

  local urls = {}
  for _, file in ipairs(files) do
    local url = repo_url .. file
    http.request(url)
    urls[url] = file
  end

  while true do
    local event, url, arg1 = os.pullEvent()
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

--- Append an object to a list if it is not already contained within
local function add_unique(list, x)
  for i = 1, #list do if list[i] == x then return end end
  list[#list + 1] = x
end

local function load_all_modules()
  -- Load all modules and update them.
  local module_dir = fs.combine(root_dir, "modules")
  local modules = fs.isDir(module_dir) and fs.list(module_dir) or {}

  -- Add the default modules if not already there.
  for _, module in ipairs { "lua.lua", "pager.lua", "readline.lua", "shell.lua" } do
    add_unique(modules, module)
  end

  local files = {}
  for i = 1, #modules do files[i] = "modules/" .. modules[i] end
  download_files(files)

  -- Scan for dependencies in enabled modules, downloading them as well
  local deps = {}
  for i = 1, #files do
    local module = load_module(fs.combine(root_dir, files[i]))
    if module then
      setup_module(module)
      if module.enabled() then
        for _, dep in ipairs(module.dependencies) do deps[#deps + 1] = dep end
      end
    end
  end
  download_files(deps)
end

if arg.n == 0 then
  printError("Expected some command")
  print_usage()
  error()
elseif arg[1] == "download" then
  load_all_modules()
elseif arg[1] == "install" then
  load_all_modules()

  -- Move the existing startup file. We have to read the whole thing,
  -- as otherwise we'd end up copying inside ourselves.
  if fs.exists("startup") and not fs.isDir("startup") then
    write_coloured(colours.cyan, "Moving your existing startup file to startup/30_startup.lua.\n")

    local handle = fs.open("startup", "r")
    local contents = handle.readAll()
    handle.close()
    fs.delete("startup")

    handle = fs.open("startup/30_startup.lua", "w")
    handle.write(contents)
    handle.close()
  end

  -- Also move the startup.lua file afterwards
  if fs.exists("startup.lua") and not fs.isDir("startup.lua") then
    write_coloured(colours.cyan, "Moving your existing startup.lua file to startup/31_startup.lua.\n")
    fs.move("startup.lua", "startup/31_startup.lua")
  end

  if fs.exists("startup/99_mbs.lua") then
    write_coloured(colours.cyan, "Deleting the old startup/99_mbs.lua file. We now run before other startup files.\n")
    fs.delete("startup/99_mbs.lua")
  end

  -- We'll run at the first possible position to ensure
  local handle = fs.open("startup/00_mbs.lua", "w")
  local current = shell.getRunningProgram()
  handle.writeLine(("assert(loadfile(%q, _ENV))('startup', %q)"):format(current, current))
  handle.close()

  write_coloured(colours.green, "Installed! ")
  io.write("Please reboot to apply changes.\n")
elseif arg[1] == "startup" then
  -- Gather a list of all modules
  local module_dir = fs.combine(install_dir, "modules")
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

  local current = arg[2] or shell.getRunningProgram()
  shell.setCompletionFunction(current, function(_, index, text, previous)
    if index == 1 then
      return complete_multi(text, commands, true)
    elseif index == 2 and previous[#previous] == "module" then
      return complete_multi(text, module_names, false)
    end
  end)

  -- Setup those modules
  for _, module in ipairs(enabled) do
    if type(module.setup) == "function" then module.setup(install_dir) end
  end

  -- And run the startup hook if needed
  for _, module in ipairs(enabled) do
    if type(module.startup) == "function" then module.startup(install_dir) end
  end

elseif arg[1] == "modules" then
  local module_dir = fs.combine(install_dir, "modules")
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

    io.write("\n")
  end

  if not found_any then error("No modules found. Maybe try running the `install` command?", 0) end
elseif arg[1] == "module" then
  if not arg[2] then error("Expected module name", 0) end
  local module, err = load_module(fs.combine(install_dir, fs.combine("modules", arg[2] .. ".lua")))
  if not module then error(err, 0) end

  io.write(module.description)
  if module.enabled() then
    write_coloured(colours.green, " (enabled)")
  else
    write_coloured(colours.red, " (disabled)")
  end
  io.write("\n\n")

  for _, setting in ipairs(module.settings) do
    local value = settings.get(setting.name)
    write_coloured(colours.cyan, setting.name)
    io.write(" " .. setting.description .. " (")
    write_coloured(colours.yellow, textutils.serialise(value))
    if value ~= setting.default then
      io.write(", default is \n")
      write_coloured(colours.yellow, textutils.serialise(setting.default))
    end

    io.write(")\n")
  end
else
  printError("Unknown command")
  print_usage()
  error()
end
