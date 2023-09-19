--!lua

local argv = ...
local args, opts = require("getopt").getopt({
  options = {
    help = false,
  }
}, argv)

local path = args[1]

local sys = require("syscalls")
local errno = require("posix.errno")

if opts.help or #args ~= 1 then
  io.stderr:write([[
Usage:
  umount MOUNTPOINT

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
  os.exit(1)
end

local success, err = sys.unmount(path)
if not success then
  io.stderr:write(argv[0], ": ", path, ": ", errno.errno(err), "\n")
  os.exit(1)
end
