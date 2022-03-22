--!lua
local args = ...
local device = args[1]
local mountpoint = args[2]

local sys = require("syscalls")
local errx = require("errors").err

if not mountpoint then
  io.stderr:write("Usage: "..args[0].." <device> [mountpoint]\n")
  sys.exit(1)
end

local success, err = sys.mount(device, mountpoint)
if not success then
  io.stderr:write(args[0]..": "..device..": "..errx(err))
  sys.exit(1)
end

sys.exit(0)
