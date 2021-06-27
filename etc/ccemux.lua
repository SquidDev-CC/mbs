#!/usr/bin/env lua

local function find_latest(dir)
  local launcher = io.open(dir .. "/launcher.properties", "r")
  if not launcher then return nil, "Cannot find CCEmuX" end

  local info = {}
  for line in launcher:lines() do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k then info[k] = v end
  end
  launcher:close()

  if not info.version or not info.build then return nil, "Cannot find CCEmuX version" end
  return ("%s/versions/%s/CCEmuX-%s.jar"):format(dir, info.version, info.build)
end

local function guess_path()
  local appdata = os.getenv("APPDATA")
  if appdata then return find_latest(appdata:gsub("\\", "/") .. "/ccemux") end

  local home = os.getenv("HOME") -- Probably should check XDG here too, but this works.
  if home then return find_latest(home .. "/.local/share/ccemux") end

  -- Who knows what OSX does‽ I don't.
  return nil, "Cannot find CCEmuX installation directory"
end

local ccemux_path, err = ...
if not ccemux_path then ccemux_path, err = guess_path() end
if not ccemux_path then
  io.stderr:write(err .. "\n")
  os.exit(1)
end

local cmd = ("java -jar %q -c ."):format(ccemux_path)
print("> " .. cmd)
os.execute(cmd)
