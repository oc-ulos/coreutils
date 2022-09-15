--!lua
local argv = ...

local sys = require("syscalls")
local errno = require("posix.errno")

local arg = (argv[1] and argv[1]:sub(3)) or argv[0]
local success, err

if arg == "help" then
  io.stderr:write([[
usage: poweroff OPTION
Perform some power-related operation.  If no OPTION is specified, poweroff
will act like what it was invoked as.

Options:
  --halt      Halt the system
  --poweroff  Power off the system
  --reboot    Reboot the system

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
  os.exit(1)

elseif arg == "halt" then
  success, err = sys.reboot("halt")

elseif arg == "poweroff" or argv[1] == "-p" then
  success, err = sys.reboot("poweroff")

elseif arg == "reboot" then
  success, err = sys.reboot("restart")

else
  success, err = nil, "Invalid executable name, or bad argument."
end

if not success then
  io.stderr:write(argv[0], ": ", errno.errno(err), "\n")
  os.exit(1)
end
