--!lua
-- this program more or less follows a simplified version of the path that
-- BusyBox's login does

local sys = require("syscalls")
local pwd = require("posix.pwd")
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")

local uname = sys.uname()
io.stdout:write("\n", uname.sysname, " ", uname.release, "\n")

while true do
  if not unistd.isatty(0) or not unistd.isatty(1) then
    io.stderr:write("login: refusing to run when stdin/out are not TTYs\n")
    os.exit(1)
  end

  io.stdin:flush()
  local name = ""
  while #name == 0 do
    io.write("\n" .. sys.gethostname() .. " login: ")
    name = io.stdin:read("l")
  end

  io.stdout:write("Password: ")
  sys.ioctl(0, "stty", {echo = false})
  local password = io.stdin:read("l")
  sys.ioctl(0, "stty", {echo = true})
  io.stdout:write("\n")

  local pwent = pwd.getpwnam(name)
  if pwent and (unistd.crypt(password) == pwent.pw_passwd) then
    io.write("\n")
    sys.setuid(pwent.pw_uid)
    sys.setgid(pwent.pw_gid)
    stdlib.setenv("USER", pwent.pw_name)
    stdlib.setenv("HOME", pwent.pw_dir or "/")
    stdlib.setenv("UID", tostring(pwent.pw_uid))
    stdlib.setenv("GID", tostring(pwent.pw_gid))
    stdlib.setenv("SHELL", pwent.pw_shell or "/bin/sh.lua")
    unistd.execp(pwent.pw_shell or "/bin/sh.lua", {})
  else
    io.stderr:write("bad login\n")
    unistd.sleep(3)
  end
end
