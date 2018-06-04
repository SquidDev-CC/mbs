local topic = ... or "intro"

if topic == "index" then
  print("Help topics availiable:")
  textutils.pagedTabulate(help.topics())
else
  local file_name = help.lookup(topic)
  if not file_name then error("No help available", 0) end

  local file = fs.open(file_name, "r")
  -- Shouldn't happen, but nice to handle anyway
  if not file then error("No help available", 0) end

  local contents = file.readAll()
  file.close()

  local _, height = term.getCursorPos()
  textutils.pagedPrint(contents, height - 3)
end
