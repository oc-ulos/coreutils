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

if opts.help then
  io.stderr:write(([[
Usage:
  mount
  mount DEVICE MOUNTPOINT
]]):format(argv[0]))
  os.exit(0)
end

local success, err = sys.mount(device, mountpoint)
if not success then
  io.stderr:write(argv[0], ": ", device, ": ", errno.errno(err), "\n")
  os.exit(1)
end
