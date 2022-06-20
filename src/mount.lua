--!lua

local argv = ...
local args, opts = require("getopt").getopt({
  options = {
    help = false,
  }
}, argv)
local device = args[1]
local mountpoint = args[2]

local sys = require("syscalls")
local errno = require("posix.errno")

if opts.help or #args == 1 then
  io.stderr:write(([[
Usage:
  mount
  mount DEVICE MOUNTPOINT

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(argv[0]))
  os.exit(0)
end

if #args == 0 then
  for line in io.lines("/proc/mounts") do
    print((line:gsub("([^ ]+) ([^ ]+) ([^ ]+)", "%1 type %3 on %2")))
  end

else
  local success, err = sys.mount(device, mountpoint)
  if not success then
    io.stderr:write(argv[0], ": ", device, ": ", errno.errno(err), "\n")
    os.exit(1)
  end
end
