local type = type

local colour_lookup = {}
for i = 0, 16 do
  colour_lookup[2 ^ i] = string.format("%x", i)
end

local function copy_term(from, to, get_line, cursor_offset)
  local _, sizeY = from.getSize()
  for y = 1, sizeY do
    to.setCursorPos(1, y)
    to.blit(get_line(y))
  end

  local x, y = from.getCursorPos()
  to.setCursorPos(x, y - cursor_offset)
  to.setCursorBlink(from.getCursorBlink())
  to.setTextColour(from.getTextColour())
  to.setBackgroundColour(from.getBackgroundColour())

  if from.getPaletteColour and to.getPaletteColour then
    for i = 0, 15 do
      to.setPaletteColour(2 ^ i, from.getPaletteColour(2 ^ i))
    end
  end
end
function create(original)
  if not original then original = term.current() end

  local text = {}
  local text_colour = {}
  local back_colour = {}
  local palette = {}

  local cursor_x, cursor_y = 1, 1

  local scroll_offset = 0
  local scroll_cursor_y = cursor_y

  local cursor_blink = false
  local cur_text_colour = "0"
  local cur_back_colour = "f"

  local sizeX, sizeY = original.getSize()
  local color = original.isColor()

  local max_scrollback = 100
  local bubble, delegate = true, nil

  local cursor_threshold = 0

  local redirect = {}

  if original.getPaletteColour then
    for i = 0, 15 do
      local c = 2 ^ i
      palette[c] = { original.getPaletteColour(c) }
    end
  end

  local function trim()
    if max_scrollback > -1 then
      while scroll_offset > max_scrollback do
        table.remove(text, 1)
        table.remove(text_colour, 1)
        table.remove(back_colour, 1)
        scroll_offset = scroll_offset - 1
      end
    end
    scroll_cursor_y = scroll_offset + cursor_y
  end

  function redirect.write(writeText)
    if delegate then return delegate.write(writeText) end

    writeText = tostring(writeText)
    if bubble then original.write(writeText) end

    local pos = cursor_x

    -- If we're off the screen then just emulate a write
    if cursor_y > sizeY or cursor_y < 1 then
      cursor_x = pos + #writeText
      return
    end

    if pos + #writeText <= 1 or pos > sizeX then
      -- If we're too far off the left then skip.
      cursor_x = pos + #writeText
      return
    elseif pos < 1 then
      -- Adjust text to fit on screen starting at one.
      writeText = string.sub(writeText, -pos + 2)
      pos = 1
    end

    local lineText = text[scroll_cursor_y]
    local lineColor = text_colour[scroll_cursor_y]
    local lineBack = back_colour[scroll_cursor_y]
    local preStop = pos - 1
    local preStart = math.min(1, preStop)
    local postStart = pos + #writeText
    local postStop = sizeX
    local sub, rep = string.sub, string.rep

    text[scroll_cursor_y] = sub(lineText, preStart, preStop) .. writeText .. sub(lineText, postStart, postStop)
    text_colour[scroll_cursor_y] = sub(lineColor, preStart, preStop) .. rep(cur_text_colour, #writeText) .. sub(lineColor, postStart, postStop)
    back_colour[scroll_cursor_y] = sub(lineBack, preStart, preStop) .. rep(cur_back_colour, #writeText) .. sub(lineBack, postStart, postStop)
    cursor_x = pos + #writeText
  end

  function redirect.blit(writeText, writeFore, writeBack)
    if delegate then return delegate.blit(writeText, writeFore, writeBack) end

    if type(writeText) ~= "string" then error("bad argument #1 (expected string, got " .. type(writeText) .. ")", 2) end
    if type(writeFore) ~= "string" then error("bad argument #2 (expected string, got " .. type(writeFore) .. ")", 2) end
    if type(writeBack) ~= "string" then error("bad argument #3 (expected string, got " .. type(writeBack) .. ")", 2) end
    if #writeFore ~= #writeText or #writeBack ~= #writeText then error("Arguments must be the same length", 2) end

    if bubble then original.blit(writeText, writeFore, writeBack) end

    local pos = cursor_x

    -- If we're off the screen then just emulate a write
    if cursor_y > sizeY or cursor_y < 1 then
      cursor_x = pos + #writeText
      return
    end

    if pos + #writeText <= 1 then
      --skip entirely.
      cursor_x = pos + #writeText
      return
    elseif pos < 1 then
      --adjust text to fit on screen starting at one.
      writeText = string.sub(writeText, math.abs(cursor_x) + 2)
      writeFore = string.sub(writeFore, math.abs(cursor_x) + 2)
      writeBack = string.sub(writeBack, math.abs(cursor_x) + 2)
      cursor_x = 1
    elseif pos > sizeX then
      --if we're off the edge to the right, skip entirely.
      cursor_x = pos + #writeText
      return
    else
      writeText = writeText
    end

    local lineText = text[scroll_cursor_y]
    local lineColor = text_colour[scroll_cursor_y]
    local lineBack = back_colour[scroll_cursor_y]
    local preStop = cursor_x - 1
    local preStart = math.min(1, preStop)
    local postStart = cursor_x + #writeText
    local postStop = sizeX
    local sub = string.sub

    text[scroll_cursor_y] = sub(lineText, preStart, preStop) .. writeText .. sub(lineText, postStart, postStop)
    text_colour[scroll_cursor_y] = sub(lineColor, preStart, preStop) .. writeFore .. sub(lineColor, postStart, postStop)
    back_colour[scroll_cursor_y] = sub(lineBack, preStart, preStop) .. writeBack .. sub(lineBack, postStart, postStop)
    cursor_x = pos + #writeText
  end

  function redirect.clear()
    if delegate then return delegate.clear() end

    if cursor_threshold > 0 then
      return redirect.beginPrivateMode().clear()
    end

    local text_line = (" "):rep(sizeX)
    local fore_line = cur_text_colour:rep(sizeX)
    local back_line = cur_back_colour:rep(sizeX)

    for i = scroll_offset + 1, sizeY + scroll_offset do
      text[i] = text_line
      text_colour[i] = fore_line
      back_colour[i] = back_line
    end

    if bubble then return original.clear() end
  end
  function redirect.clearLine()
    if delegate then return delegate.clearLine() end

    -- If we're off the screen then just emulate a clearLine
    if cursor_y > sizeY or cursor_y < 1 then
      return
    end

    text[scroll_cursor_y] = string.rep(" ", sizeX)
    text_colour[scroll_cursor_y] = string.rep(cur_text_colour, sizeX)
    back_colour[scroll_cursor_y] = string.rep(cur_back_colour, sizeX)

    if bubble then return original.clearLine() end
  end

  function redirect.getCursorPos()
    if delegate then return delegate.getCursorPos() end
    return cursor_x, cursor_y
  end

  function redirect.setCursorPos(x, y)
    if delegate then return delegate.setCursorPos(x, y) end

    if type(x) ~= "number" then error("bad argument #1 (expected number, got " .. type(x) .. ")", 2) end
    if type(y) ~= "number" then error("bad argument #2 (expected number, got " .. type(y) .. ")", 2) end

    local new_y = math.floor(y)
    if new_y >= 1 and new_y < cursor_threshold then
      -- If we're writing within a protected region then start a private buffer
      return redirect.beginPrivateMode().setCursorPos(x, y)
    end

    cursor_x = math.floor(x)
    cursor_y = new_y
    scroll_cursor_y = new_y + scroll_offset

    if bubble then return original.setCursorPos(x, y) end
  end

  function redirect.setCursorBlink(b)
    if delegate then return delegate.setCursorBlink(b) end

    if type(b) ~= "boolean" then error("bad argument #1 (expected boolean, got " .. type(b) .. ")", 2) end

    cursor_blink = b
    if bubble then return original.setCursorBlink(b) end
  end

  function redirect.getCursorBlink()
    if delegate then return delegate.getCursorBlink() end
    return cursor_blink
  end

  function redirect.getSize()
    if delegate then return delegate.getSize() end

    return sizeX, sizeY
  end

  function redirect.scroll(n)
    if delegate then return delegate.scroll(n) end

    if type(n) ~= "number" then error("bad argument #1 (expected number, got " .. type(n) .. ")", 2) end

    if n > 0 then
      scroll_offset = scroll_offset + n
      for i = sizeY + scroll_offset - n + 1, sizeY + scroll_offset do
        text[i] = string.rep(" ", sizeX)
        text_colour[i] = string.rep(cur_text_colour, sizeX)
        back_colour[i] = string.rep(cur_back_colour, sizeX)
      end

      trim()
    elseif n < 0 then
      for i = sizeY + scroll_cursor_y, math.abs(n) + 1 + scroll_cursor_y, -1 do
        if text[i + n] then
          text[i] = text[i + n]
          text_colour[i] = text_colour[i + n]
          back_colour[i] = back_colour[i + n]
        end
      end

      for i = scroll_cursor_y, math.abs(n) + scroll_cursor_y do
        text[i] = string.rep(" ", sizeX)
        text_colour[i] = string.rep(cur_text_colour, sizeX)
        back_colour[i] = string.rep(cur_back_colour, sizeX)
      end
    end

    cursor_threshold = cursor_threshold - n

    if bubble then return original.scroll(n) end
  end

  function redirect.setTextColour(clr)
    if delegate then return delegate.setTextColour(clr) end

    if type(clr) ~= "number" then error("bad argument #1 (expected number, got " .. type(clr) .. ")", 2) end
    cur_text_colour = colour_lookup[clr] or error("Invalid colour (got " .. clr .. ")" , 2)
    if bubble then return original.setTextColour(clr) end
  end
  redirect.setTextColor = redirect.setTextColour

  function redirect.setBackgroundColour(clr)
    if delegate then return delegate.setBackgroundColour(clr) end

    if type(clr) ~= "number" then error("bad argument #1 (expected number, got " .. type(clr) .. ")", 2) end
    cur_back_colour = colour_lookup[clr] or error("Invalid colour (got " .. clr .. ")" , 2)
    if bubble then return original.setBackgroundColour(clr) end
  end
  redirect.setBackgroundColor = redirect.setBackgroundColour

  function redirect.isColour()
    if delegate then return delegate.isColour() end
    return color == true
  end
  redirect.isColor = redirect.isColour

  function redirect.getTextColour()
    if delegate then return delegate.getTextColour() end
    return 2 ^ tonumber(cur_text_colour, 16)
  end
  redirect.getTextColor = redirect.getTextColour

  function redirect.getBackgroundColour()
    if delegate then return delegate.getBackgroundColour() end
    return 2 ^ tonumber(cur_back_colour, 16)
  end
  redirect.getBackgroundColor = redirect.getBackgroundColour

  if original.getPaletteColour then
    function redirect.setPaletteColour(colour, r, g, b)
      if delegate then return delegate.setPaletteColour(colour, r, g, b) end

      local palcol = palette[colour]
      if not palcol then error("Invalid colour (got " .. tostring(colour) .. ")", 2) end
      if type(r) == "number" and g == nil and b == nil then
          palcol[1], palcol[2], palcol[3] = colours.rgb8(r)
      else
          if type(r) ~= "number" then error("bad argument #2 (expected number, got " .. type(r) .. ")", 2) end
          if type(g) ~= "number" then error("bad argument #3 (expected number, got " .. type(g) .. ")", 2) end
          if type(b) ~= "number" then error("bad argument #4 (expected number, got " .. type(b) .. ")", 2) end

          palcol[1], palcol[2], palcol[3] = r, g, b
      end

      if bubble then return original.setPaletteColour(colour, r, g, b) end
    end
    redirect.setPaletteColor = redirect.setPaletteColour

    function redirect.getPaletteColour(colour)
      if delegate then return delegate.getPaletteColour(colour) end

      local palcol = palette[colour]
      if not palcol then error("Invalid colour (got " .. tostring(colour) .. ")", 2) end
      return palcol[1], palcol[2], palcol[3]
    end
    redirect.getPaletteColor = redirect.getPaletteColour
  end

  function redirect.draw(offset, clear)
    if delegate then return end

    local scroll_offset = scroll_offset + (offset or 0)
    copy_term(redirect, original, function(i)
      local yOffset = scroll_offset + i
      return text[yOffset], text_colour[yOffset], back_colour[yOffset]
    end, offset)
  end

  function redirect.bubble(b)
    bubble = b
  end

  function redirect.setCursorThreshold(y)
    cursor_threshold = y
  end

  function redirect.endPrivateMode(redraw)
    if delegate then
      local old_delegate = delegate
      delegate = nil
      redirect.draw(0)

      -- If we should redraw the old buffer then blit it to the canvas
      if redraw then
        if cursor_threshold > 0 then
          redirect.scroll(cursor_threshold)
        end

        copy_term(old_delegate, redirect, old_delegate.getLine, 0)
      end
    end
  end

  function redirect.beginPrivateMode()
    if not delegate then
      delegate = window.create(original, 1, 1, sizeX, sizeY, false)

      for y = 1, sizeY do
        delegate.setCursorPos(1, y)
        delegate.blit(text[y + scroll_offset], text_colour[y + scroll_offset], back_colour[y + scroll_offset])
      end

      delegate.setCursorPos(cursor_x, cursor_y)
      delegate.setCursorBlink(cursor_blink)
      delegate.setTextColour(2 ^ tonumber(cur_text_colour, 16))
      delegate.setBackgroundColor(2 ^ tonumber(cur_back_colour, 16))

      if original.getPaletteColour then
        for i = 0, 15 do
          local palcol = palette[2 ^ i]
          delegate.setPaletteColour(2 ^ i, palcol[1], palcol[2], palcol[3])
        end
      end

      delegate.setVisible(true)
    end

    return delegate
  end

  function redirect.isPrivateMode()
    return delegate ~= nil
  end

  function redirect.getTotalHeight() return scroll_offset end

  function redirect.setMaxScrollback(n)
    local old_scrollback = max_scrollback
    max_scrollback = n

    if old_scrollback > max_scrollback then trim() end
  end

  function redirect.updateSize()
    -- If nothing has changed then just skip.
    local new_x, new_y = original.getSize()

    if new_x == sizeX and new_y == sizeY then return end

    -- Update the delegate window.
    if delegate then delegate.reposition(1, 1, new_x, new_y) end

    -- If we have an insufficient number of lines then add some in.
    local total_height = #text

    -- For any existing lines, trim them
    for y = 1, total_height do
      if new_x < sizeX then
        text[y] = text[y]:sub(1, new_x)
        text_colour[y] = text_colour[y]:sub(1, new_x)
        back_colour[y] = back_colour[y]:sub(1, new_x)
      elseif new_x > sizeX then
        text[y] = text[y] .. (" "):rep(new_x - sizeX)
        text_colour[y] = text_colour[y] .. cur_text_colour:rep(new_x - sizeX)
        back_colour[y] = back_colour[y] .. cur_back_colour:rep(new_x - sizeX)
      end
    end

    if new_y > sizeY then
      -- Append any new lines we might need.
      local text_line = (" "):rep(new_x)
      local fore_line = cur_text_colour:rep(new_x)
      local back_line = cur_back_colour:rep(new_x)
      for y = total_height + 1, new_y do
        text[y] = text_line
        text_colour[y] = fore_line
        back_colour[y] = back_line
      end
    elseif new_y < sizeY then
      -- Move the cursor "up" the screen, as we're going to scroll the rest of
      -- the terminal up.
      -- Note, this is a little ugly (we lose the top of the screen even if we)
      -- don't need to, but it's the best we can do for now.
      cursor_y = cursor_y - sizeY + new_y
      cursor_threshold = cursor_threshold - sizeY + new_y
    end

    sizeX = new_x
    sizeY = new_y

    -- Update the scroll offset. For now we just go back to the bottom
    scroll_offset = #text - sizeY
    scroll_cursor_y = scroll_offset + cursor_y
    trim()
  end

  redirect.clear()
  return redirect
end
