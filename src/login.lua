-- login --

local pwd = require("posix.pwd")
local unistd = require("posix.unistd")

while true do
  if not unistd.isatty(0) or not unistd.isatty(1) then
    io.stderr:write("login: refusing to run when stdin/out are not TTYs\n")
    os.exit(1)
  end

  io.stdin:flush()
  local name = ""
  while #name == 0 do
    io.stdout:write("\n", unistd.gethostname(), " login: ")
    name = io.stdin:read("l")
  end

  local password = ""
end
