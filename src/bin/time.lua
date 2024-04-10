--!lua
-- time

local argv = ...

local sys = require("syscalls")
local wait = require("posix.sys.wait")
local unistd = require("posix.unistd")

local uptime = sys.uptime()

local pid, err = sys.fork(function()
  argv[0] = table.remove(argv, 1)
  assert(unistd.execp(argv[0], argv))
end)

if not pid then
  io.stderr:write(err)
else
  local a, b, c = wait.wait(pid)
end

print("real", sys.uptime() - uptime)
