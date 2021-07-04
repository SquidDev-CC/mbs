local debug_traceback = type(debug) == "table" and type(debug.traceback) == "function" and debug.traceback

--- Run a function with a traceback.
local function xpcall_with(fn)
  -- So this is rather grim: we need to get the full traceback and current one and remove
  -- the common prefix
  local co = coroutine.create(fn)
  local args, result = { n = 0 }
  while true do
    result = table.pack(coroutine.resume(co, table.unpack(args, 1, args.n)))

    if not result[1] then break end
    if coroutine.status(co) == "dead" then return table.unpack(result, 1, result.n) end

    args = table.pack(coroutine.yield(result[2]))
  end

  if debug_traceback then
    return false, debug_traceback(co, result[2])
  else
    return false, result[2]
  end
end

_ENV.xpcall_with = xpcall_with
