--!lua
local args = ...

local sys = require("syscalls")
local errx = require("errors").errx

if #args == 0 then
  io.stderr:write("Usage: " .. args[0] .. " <path>\n")
  sys.exit(1)
end

local success, err = sys.mkdir(args[1])
if not success then
  io.stderr:write(args[0]..": "..errx(err).."\n")
  sys.exit(1)
end

sys.exit(0)
