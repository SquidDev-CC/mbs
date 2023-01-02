local path = "/" .. fs.getDir(shell.getRunningProgram()) .. "/shell-worker.lua"
if select('#', ...) > 0 then
    shell.execute("/rom/programs/shell", ...)
else
    shell.execute("/rom/programs/shell", path, ...)
end
