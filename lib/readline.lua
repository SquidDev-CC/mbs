
--- A mapping of colours, to aid reading settings.
local colour_table = { }

for k, v in pairs(colours) do
  if type(v) == "number" then colour_table[k] = v end
end

for k, v in pairs(colors) do
  if type(v) == "number" then colour_table[k] = v end
end

--- Keys which are used in combinations involving the "meta" key.
local meta_keys = "ulcdbf"

--- Clamp a [value] within a range
local function clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

--- Verify a [tbl] has a [key] of nil or the given [type]
local type = type
local function check_key(tbl, key, ty)
   local actual_type = type(tbl[key])
   if actual_type ~= "nil" and actual_type ~= ty then
    error(("bad key %s (expected %s, got %s)"):format(key, ty, actual_type), 3)
  end
end

function read(opts)
  if opts == nil then
    opts = {}
  elseif type(opts) ~= "table" then
    error("bad argument #1 (expected table, got " .. type(opts) .. ")", 2)
  end

  check_key(opts, "replace_char", "string") -- Character to show instead
  check_key(opts, "history", "table") -- List of previous items
  check_key(opts, "complete", "function") -- Completion function
  check_key(opts, "default", "string") -- Initial string
  check_key(opts, "complete_fg", "number") -- Foreground for completion
  check_key(opts, "complete_bg", "number") -- Background for completion

  -- Highlight function: (line: string, start: number) -> (end: number, colour:colour)
  check_key(opts, "highlight", "function")

  local w = term.getSize()
  local sx = term.getCursorPos()

  local sLine = opts.default or ""
  local nPos, nScroll = #sLine, 0
  local tKillRing, nKillRing = {}, 0

  local nHistoryPos
  local tDown = {}
  local nMod = 0
  local replace_char = opts.replace_char and opts.replace_char:sub(1, 1)
  local complete_fg = opts.complete_fg or colour_table[settings.get("mbs.readline.complete_fg")] or -1
  local complete_bg = opts.complete_bg or colour_table[settings.get("mbs.readline.complete_bg")] or -1

  local tCompletions
  local nCompletion
  local function recomplete()
    if opts.complete and nPos == #sLine then
      tCompletions = opts.complete(sLine)
      if tCompletions and #tCompletions > 0 then
        nCompletion = 1
      else
        nCompletion = nil
      end
    else
      tCompletions = nil
      nCompletion = nil
    end
  end

  local function uncomplete()
    tCompletions = nil
    nCompletion = nil
  end

  local function updateModifier()
    nMod = 0
    if tDown[keys.leftCtrl] or tDown[keys.rightCtrl] then nMod = nMod + 1 end
    if tDown[keys.leftAlt] or tDown[keys.rightAlt]   then nMod = nMod + 2 end
  end

  local function nextWord()
    -- Attempt to find the position of the next word
    local nOffset = sLine:find("%w%W", nPos + 1)
    if nOffset then return nOffset else return #sLine end
  end

  local function prevWord()
    -- Attempt to find the position of the previous word
    local nOffset = 1
    while nOffset <= #sLine do
      local nNext = sLine:find("%W%w", nOffset)
      if nNext and nNext < nPos then
        nOffset = nNext + 1
      else
        break
      end
    end
    return nOffset - 1
  end

  local function redraw(_bClear)
    local cursor_pos = nPos - nScroll
    if sx + cursor_pos >= w then
      -- We've moved beyond the RHS, ensure we're on the edge.
      nScroll = sx + nPos - w
    elseif cursor_pos < 0 then
      -- We've moved beyond the LHS, ensure we're on the edge.
      nScroll = nPos
    end

    local _, cy = term.getCursorPos()
    term.setCursorPos(sx, cy)
    local sReplace = _bClear and " " or replace_char

    if opts.highlight and not _bClear then
      -- We've a highlighting function: step through each line of input
      local old_col = term.getTextColor()
      local hl_pos, hl_max, hl_col = 1, #sLine, old_col
      while hl_pos <= hl_max do
        local next_pos, next_col = opts.highlight(sLine, hl_pos)
        if next_pos < hl_pos then error("Highlighting function consumed no input") end

        if next_pos >= nScroll + 1 then
          if next_col ~= hl_col then term.setTextColor(next_col) hl_col = next_col end
          if sReplace then
            term.write(string.rep(sReplace, next_pos - math.max(nScroll + 1, hl_pos) + 1))
          else
            term.write(string.sub(sLine, math.max(nScroll + 1, hl_pos), next_pos))
          end
        end

        hl_pos = next_pos + 1
      end
      term.setTextColor(old_col)
    else
      -- If we've no highlighting function, we can go the "fast" path.
      if sReplace then
        term.write(string.rep(sReplace, math.max(#sLine - nScroll, 0)))
      else
        term.write(string.sub(sLine, nScroll + 1))
      end
    end

    if nCompletion then
      local sCompletion = tCompletions[ nCompletion ]
      local oldText, oldBg
      if not _bClear then
        oldText = term.getTextColor()
        oldBg = term.getBackgroundColor()
        if complete_fg > -1 then term.setTextColor(complete_fg) end
        if complete_bg > -1 then term.setBackgroundColor(complete_bg) end
      end
      if sReplace then
        term.write(string.rep(sReplace, #sCompletion))
      else
        term.write(sCompletion)
      end
      if not _bClear then
        term.setTextColor(oldText)
        term.setBackgroundColor(oldBg)
      end
    end

    term.setCursorPos(sx + nPos - nScroll, cy)
  end

  local function nsub(start, fin)
    if start < 1 or fin < start then return "" end
    return sLine:sub(start, fin)
  end

  local function clear()
    redraw(true)
  end

  local function kill(text)
    if #text == "" then return end
    nKillRing = nKillRing + 1
    tKillRing[nKillRing] = text
  end

  local function acceptCompletion()
    if nCompletion then
      -- Clear
      clear()

      -- Find the common prefix of all the other suggestions which start with the same letter as the current one
      local sCompletion = tCompletions[ nCompletion ]
      sLine = sLine .. sCompletion
      nPos = #sLine

      -- Redraw
      recomplete()
      redraw()
    end
  end

  term.setCursorBlink(true)
  recomplete()
  redraw()
  while true do
    local sEvent, param, param1, param2 = os.pullEvent()
    if sEvent == "char" and (nMod == 0 or nMod == 3 or nMod == 2 and not meta_keys:find(param, 1, true)) then
      -- Typed key
      -- Alt+X will queue a char event, so we limit ourselves to cases where
      -- no modifier is used, or Ctrl+Alt are (equivalent to AltGr), or the Alt
      -- key is used and we have no known combination.
      clear()
      sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
      nPos = nPos + 1
      recomplete()
      redraw()
    elseif sEvent == "paste" then
      -- Pasted text
      clear()
      sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
      nPos = nPos + #param
      recomplete()
      redraw()
    elseif sEvent == "key" then
      -- All keybindigns within the read loop.
      -- IMPORTANT: Please update the meta_keys variable up top. Ideally we'd
      -- make each function operate on a state, and run outside the loop, but
      -- this will do for now.
      if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
        tDown[param] = true
        updateModifier()
      elseif param == keys.enter then
        -- Enter
        if nCompletion then
          clear()
          uncomplete()
          redraw()
        end
        break

      -- Moving through text/completions
      elseif nMod == 1 and param == keys.d then
        -- End of stream, abort
        if nCompletion then
          clear()
          uncomplete()
          redraw()
        end
        sLine = nil
        nPos = 0
        break
      elseif nMod == 0 and param == keys.left or nMod == 1 and param == keys.b then
        -- Left
        if nPos > 0 then
          clear()
          nPos = nPos - 1
          recomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys.right or nMod == 1 and param == keys.f then
        -- Right
        if nPos < #sLine then
          -- Move right
          clear()
          nPos = nPos + 1
          recomplete()
          redraw()
        else
          -- Accept autocomplete
          acceptCompletion()
        end
      elseif nMod == 2 and param == keys.b then
        -- Word left
        local nNewPos = prevWord()
        if nNewPos ~= nPos then
          clear()
          nPos = nNewPos
          recomplete()
          redraw()
        end
      elseif nMod == 2 and param == keys.f then
        -- Word right
        local nNewPos = nextWord()
        if nNewPos ~= nPos then
          clear()
          nPos = nNewPos
          recomplete()
          redraw()
        end
      elseif nMod == 0 and (param == keys.up or param == keys.down)
          or nMod == 1 and (param == keys.p or param == keys.n) then
        -- Up or down
        if nCompletion then
          -- Cycle completions
          clear()
          if param == keys.up or param == keys.p then
            nCompletion = nCompletion - 1
            if nCompletion < 1 then
              nCompletion = #tCompletions
            end
          elseif param == keys.down or param == keys.n then
            nCompletion = nCompletion + 1
            if nCompletion > #tCompletions then
              nCompletion = 1
            end
          end
          redraw()
        elseif opts.history then
          -- Cycle history
          clear()
          if param == keys.up or param == keys.p then
            -- Up
            if nHistoryPos == nil then
              if #opts.history > 0 then
                nHistoryPos = #opts.history
              end
            elseif nHistoryPos > 1 then
              nHistoryPos = nHistoryPos - 1
            end
          elseif param == keys.down or param == keys.n then
            -- Down
            if nHistoryPos == #opts.history then
              nHistoryPos = nil
            elseif nHistoryPos ~= nil then
              nHistoryPos = nHistoryPos + 1
            end
          end
          if nHistoryPos then
            sLine = opts.history[nHistoryPos]
            nPos, nScroll = #sLine, 0
          else
            sLine = ""
            nPos, nScroll = 0, 0
          end
          uncomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys.home
          or nMod == 1 and param == keys.a then
        -- Home
        if nPos > 0 then
          clear()
          nPos = 0
          recomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys["end"]
          or nMod == 1 and param == keys.e then
        -- End
        if nPos < #sLine then
          clear()
          nPos = #sLine
          recomplete()
          redraw()
        end
      -- Changing text
      elseif nMod == 1 and param == keys.t then
        -- Transpose char
        local prev, cur
        if nPos == #sLine then prev, cur = nPos - 1, nPos
        elseif nPos == 0 then prev, cur = 1, 2
        else prev, cur = nPos, nPos + 1
        end

        sLine = nsub(1, prev - 1) .. nsub(cur, cur) .. nsub(prev, prev) .. nsub(cur + 1, #sLine)
        nPos = math.min(#sLine, cur)

        -- We need the clear to remove the completion
        clear() recomplete() redraw()
      elseif nMod == 2 and param == keys.u then
        -- Upcase word
        if nPos < #sLine then
          local nNext = nextWord()
          sLine = nsub(1, nPos) .. nsub(nPos + 1, nNext):upper() .. nsub(nNext + 1, #sLine)
          nPos = nNext
          clear() recomplete() redraw()
        end
      elseif nMod == 2 and param == keys.l then
        -- Lowercase word
        if nPos < #sLine then
          local nNext = nextWord()
          sLine = nsub(1, nPos) .. nsub(nPos + 1, nNext):lower() .. nsub(nNext + 1, #sLine)
          nPos = nNext
          clear() recomplete() redraw()
        end
      elseif nMod == 2 and param == keys.c then
        -- Capitalize word
        if nPos < #sLine then
          local nNext = nextWord()
          sLine = nsub(1, nPos) .. nsub(nPos + 1, nPos + 1):upper()
               .. nsub(nPos + 2, nNext):lower() .. nsub(nNext + 1, #sLine)
          nPos = nNext
          clear() recomplete() redraw()
        end

      -- Killing text
      elseif nMod == 0 and param == keys.backspace then
        -- Backspace
        if nPos > 0 then
          clear()
          sLine = string.sub(sLine, 1, nPos - 1) .. string.sub(sLine, nPos + 1)
          nPos = nPos - 1
          if nScroll > 0 then nScroll = nScroll - 1 end
          recomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys.delete then
        -- Delete
        if nPos < #sLine then
          clear()
          sLine = string.sub(sLine, 1, nPos) .. string.sub(sLine, nPos + 2)
          recomplete()
          redraw()
        end
      elseif nMod == 1 and param == keys.u then
        -- Delete from cursor to beginning of line
        if nPos > 0 then
          clear()
          kill(sLine:sub(1, nPos))
          sLine = sLine:sub(nPos + 1)
          nPos = 0
          recomplete() redraw()
        end
      elseif nMod == 1 and param == keys.k then
        -- Delete from cursor to end of line
        if nPos < #sLine then
          clear()
          kill(sLine:sub(nPos + 1))
          sLine = sLine:sub(1, nPos)
          nPos = #sLine
          recomplete() redraw()
        end
      elseif nMod == 2 and param == keys.d then
        -- Delete from cursor to end of next word
        if nPos < #sLine then
            local nNext = nextWord()
            if nNext ~= nPos then
              clear()
              kill(sLine:sub(nPos + 1, nNext))
              sLine = sLine:sub(1, nPos) .. sLine:sub(nNext + 1)
              recomplete() redraw()
            end
        end
      elseif nMod == 1 and param == keys.w then
        -- Delete from cursor to beginning of previous word
        if nPos > 0 then
          local nPrev = prevWord(nPos)
          if nPrev ~= nPos then
            clear()
            kill(sLine:sub(nPrev + 1, nPos))
            sLine = sLine:sub(1, nPrev) .. sLine:sub(nPos + 1)
            nPos = nPrev
            recomplete()redraw()
          end
        end
      elseif nMod == 1 and param == keys.y then
        local insert = tKillRing[nKillRing]
        if insert then
          clear()
          sLine = sLine:sub(1, nPos) .. insert .. sLine:sub(nPos + 1)
          nPos = nPos + #insert
          recomplete() redraw()
        end
      -- Misc
      elseif nMod == 0 and param == keys.tab then
        -- Tab (accept autocomplete)
        acceptCompletion()
      end
    elseif sEvent == "key_up" then
      -- Update the status of the modifier flag
      if param == keys.leftCtrl or param == keys.rightCtrl
      or param == keys.leftAlt or param == keys.rightAlt then
        tDown[param] = false
        updateModifier()
      end
    elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
      local _, cy = term.getCursorPos()
      if param2 == cy then
        -- We first clamp the x position with in the start and end points
        -- to ensure we don't scroll beyond the visible region.
        local x = clamp(param1, sx, w)

        -- Then ensure we don't scroll beyond the current line
        nPos = clamp(nScroll + x - sx, 0, #sLine)

        redraw()
      end
    elseif sEvent == "term_resize" then
      -- Terminal resized
      w = term.getSize()
      redraw()
    end
  end

  local _, cy = term.getCursorPos()
  term.setCursorBlink(false)
  term.setCursorPos(w + 1, cy)
  print()

  return sLine
end
