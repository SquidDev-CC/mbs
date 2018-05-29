# Mildly better shell

MBS is a series of utilities for improving the default CraftOS experience.

## Features

### Lua REPL extensions
#### Improved serialisation
![](img/00-lua-serialise.png "Improved serialisation")

#### Reuse previous expressions
![](img/01-lua-previous.png "Reuse previous expressions")

#### Stack traces
![](img/02-lua-traceback.png "Stack traces in the REPL")

### `read` improvements
#### readline keybindings
![](img/10-readline-movement.gif "readline like keybindings")

### Shell extensions
#### Better program resolution and completion
![](img/20-shell-better-completion.png "Better program resolution and completion")

#### Improved support for fullscreen programs
![](img/21-shell-fullscreen.gif "Improved support for fullscreen programs")

#### Even works when a program errors!
![](img/23-shell-error.gif "A fullscreen program erroring")

#### Scrollback to view output of long commands
![](img/22-shell-scroll.gif "Scrollback to view output of long commands")

#### Stack traces
![](img/24-shell-deep-error.png "A program with a large stack trace erroring")

## Install
 - `wget https://raw.githubusercontent.com/SquidDev-CC/mbs/master/mbs.lua mbs.lua`
 - `mbs.lua install`
 - Restart your computer