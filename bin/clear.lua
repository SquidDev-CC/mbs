local term = term.current()

if type(term.setCursorThreshold) == "function" then
  term.setCursorThreshold(-1)
end

term.setCursorPos(1, 1)
term.clear()
