--- Additional readline

local complete_fg = colours.grey
local complete_bg = -1

local colour_table = {
  ["default"] = -1,
}

for k, v in pairs(colours) do
  if type(v) == "number" then colour_table[k] = v end
end

for k, v in pairs(colors) do
  if type(v) == "number" then colour_table[k] = v end
end

local function read(_sReplaceChar, _tHistory, _fnComplete, _sDefault)
  if _sReplaceChar ~= nil and type(_sReplaceChar) ~= "string" then
    error("bad argument #1 (expected string, got " .. type(_sReplaceChar) .. ")", 2)
  end
  if _tHistory ~= nil and type(_tHistory) ~= "table" then
    error("bad argument #2 (expected table, got " .. type(_tHistory) .. ")", 2)
  end
  if _fnComplete ~= nil and type(_fnComplete) ~= "function" then
    error("bad argument #3 (expected function, got " .. type(_fnComplete) .. ")", 2)
  end
  if _sDefault ~= nil and type(_sDefault) ~= "string" then
    error("bad argument #4 (expected string, got " .. type(_sDefault) .. ")", 2)
  end
  term.setCursorBlink(true)

  local sLine
  if type(_sDefault) == "string" then
    sLine = _sDefault
  else
    sLine = ""
  end
  local nHistoryPos
  local nPos = #sLine
  local tDown = {}
  local nMod = 0
  if _sReplaceChar then
    _sReplaceChar = string.sub(_sReplaceChar, 1, 1)
  end

  local tCompletions
  local nCompletion
  local function recomplete()
    if _fnComplete and nPos == #sLine then
      tCompletions = _fnComplete(sLine)
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

  local w = term.getSize()
  local sx = term.getCursorPos()

  local function redraw(_bClear)
    local nScroll = 0
    if sx + nPos >= w then
      nScroll = (sx + nPos) - w
    end

    local cx,cy = term.getCursorPos()
    term.setCursorPos(sx, cy)
    local sReplace = (_bClear and " ") or _sReplaceChar
    if sReplace then
      term.write(string.rep(sReplace, math.max(#sLine - nScroll, 0)))
    else
      term.write(string.sub(sLine, nScroll + 1))
    end

    if nCompletion then
      local sCompletion = tCompletions[ nCompletion ]
      local oldText, oldBg
      if not _bClear then
        oldText = term.getTextColor()
        oldBg = term.getBackgroundColor()
        if complete_fg >= 0 then term.setTextColor(complete_fg) end
        if complete_bg >= 0 then term.setBackgroundColor(completeg) end
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

  local function clear()
    redraw(true)
  end

  recomplete()
  redraw()

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
  while true do
    local sEvent, param = os.pullEvent()
    if nMod == 0 and sEvent == "char" then
      -- Typed key
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
      elseif nMod == 1 and param == keys.d then
        -- Enter
        if nCompletion then
          clear()
          uncomplete()
          redraw()
        end
        sLine = nil
        nPos = 0
        break
      elseif (nMod == 0 and param == keys.left) or (nMod == 1 and param == keys.b) then
        -- Left
        if nPos > 0 then
          clear()
          nPos = nPos - 1
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and param == keys.right) or (nMod == 1 and param == keys.f) then
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
      elseif (nMod == 0 and (param == keys.up or param == keys.down)) or (nMod == 1 and (param == keys.p or param == keys.n)) then
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
        elseif _tHistory then
          -- Cycle history
          clear()
          if param == keys.up or param == keys.p then
            -- Up
            if nHistoryPos == nil then
              if #_tHistory > 0 then
                nHistoryPos = #_tHistory
              end
            elseif nHistoryPos > 1 then
              nHistoryPos = nHistoryPos - 1
            end
          elseif param == keys.down or param == keys.n then
            -- Down
            if nHistoryPos == #_tHistory then
              nHistoryPos = nil
            elseif nHistoryPos ~= nil then
              nHistoryPos = nHistoryPos + 1
            end
          end
          if nHistoryPos then
            sLine = _tHistory[nHistoryPos]
            nPos = #sLine
          else
            sLine = ""
            nPos = 0
          end
          uncomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys.backspace then
        -- Backspace
        if nPos > 0 then
          clear()
          sLine = string.sub(sLine, 1, nPos - 1) .. string.sub(sLine, nPos + 1)
          nPos = nPos - 1
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and param == keys.home) or (nMod == 1 and param == keys.a) then
        -- Home
        if nPos > 0 then
          clear()
          nPos = 0
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
      elseif (nMod == 0 and param == keys["end"]) or (nMod == 1 and param == keys.e) then
        -- End
        if nPos < #sLine then
          clear()
          nPos = #sLine
          recomplete()
          redraw()
        end
      elseif nMod == 1 and param == keys.u then
        -- Delete from cursor to beginning of line
        if nPos > 0 then
          clear()
          sLine = sLine:sub(nPos + 1)
          nPos = 0
          recomplete()
          redraw()
        end
      elseif nMod == 1 and param == keys.k then
        -- Delete from cursor to end of line
        if nPos < #sLine then
          clear()
          sLine = sLine:sub(1, nPos)
          nPos = #sLine
          recomplete()
          redraw()
        end
      elseif nMod == 2 and param == keys.d then
        -- Delete from cursor to end of next word
        if nPos < #sLine then
            local nNext = nextWord()
            if nNext ~= nPos then
              clear()
              sLine = sLine:sub(1, nPos) .. sLine:sub(nNext + 1)
              recomplete()
              redraw()
            end
        end
      elseif nMod == 1 and param == keys.w then
        -- Delete from cursor to beginning of previous word
        if nPos > 0 then
          local nPrev = prevWord(nPos)
          if nPrev ~= nPos then
            clear()
            sLine = sLine:sub(1, nPrev) .. sLine:sub(nPos + 1)
            nPos = nPrev
            recomplete()
            redraw()
          end
        end
      elseif nMod == 0 and param == keys.tab then
        -- Tab (accept autocomplete)
        acceptCompletion()
      end
    elseif sEvent == "key_up" then
      -- Update the status of the modifier flag
      if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
        tDown[param] = false
        updateModifier()
      end
    elseif sEvent == "term_resize" then
      -- Terminal resized
      w = term.getSize()
      redraw()
    end
  end

  local cx, cy = term.getCursorPos()
  term.setCursorBlink(false)
  term.setCursorPos(w + 1, cy)
  print()

  return sLine
end

return {
  description =
    "This module extends the default read function, adding keybindings similar to " ..
    "those provided by Emacs or GNU readline as well as additional configuration options.",

  dependencies = {},

  settings = {
    {
      name = "mbs.readline.enabled",
      description = "Whether the readline module is enabled.",
      default = true,
    },
    {
      name = "mbs.readline.complete_bg",
      description = "The background colour for completions.",
      default = "default",
    },
    {
      name = "mbs.readline.complete_fg",
      description = "The foreground colour for completions.",
      default = "grey",
    }
  },

  install = function()
    complete_bg = colour_table[settings.get("mbs.readline.complete_bg")] or -1
    complete_fg = colour_table[settings.get("mbs.readline.complete_fg")] or -1

    if settings.get("mbs.readline.enabled") then
      _G.read = read
    end
  end,
}
