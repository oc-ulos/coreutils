--!lua
local args = ...

local sys = require("syscalls")
local stdio = require("stdio")

if #args == 0 then
  io.stderr:write("Usage: " .. args[0] .. " <path>\n")
  sys.exit(1)
end

for i=1, #args do
  local path = args[i]
  local fd, err = io.open(path, "r")
  if fd then
    local data = fd:read("a")
    io.write(data)
    fd:close()
  else
    io.stderr:write(string.format(stdio.stderr, "%s: %s: %s\n",
      args[0], path, err))
  end
end

sys.exit(0)
