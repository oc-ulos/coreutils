--!lua
-- now more or less does something SysV-adjacent

local sys = require("syscalls")
local pwd = require("posix.pwd")
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")

local args, opts, usage = require("getopt").process {
  {"User is preauthenticated", false, "f"},
  args = ...
}

if sys.getuid() ~= 0 then
  unistd.sleep(3)
  os.exit(1)
end

if opts.f and not args[1] then
  io.stderr:write("login: username not given for -f\n")
  os.exit(2)
end

if not unistd.isatty(0) or not unistd.isatty(1) then
  io.stderr:write("login: refusing to run when stdin/out are not TTYs\n")
  os.exit(1)
end

io.stdin:flush()
local name = args[1] or ""
while #name == 0 do
  io.write("login: ")
  name = io.stdin:read("l")
end

local pwent = pwd.getpwnam(name)
local password
if not opts.f then
  io.stdout:write("Password: ")
  sys.ioctl(0, "stty", {echo = false})
  password = io.stdin:read("l")
  sys.ioctl(0, "stty", {echo = true})
  io.stdout:write("\n")
end

if pwent and (opts.f or (unistd.crypt(password) == pwent.pw_passwd)) then
  io.write("\n")
  sys.setuid(pwent.pw_uid)
  sys.setgid(pwent.pw_gid)
  sys.ioctl(0, "setlogin", pwent.pw_uid)
  sys.setsid()
  stdlib.setenv("USER", pwent.pw_name)
  stdlib.setenv("HOME", pwent.pw_dir or "/")
  stdlib.setenv("UID", tostring(pwent.pw_uid))
  stdlib.setenv("GID", tostring(pwent.pw_gid))
  local shell = pwent.pw_shell or "/bin/sh.lua"
  stdlib.setenv("SHELL", shell)
  unistd.execp(shell, {[0] = "-"..shell, "--login"})

else
  io.stderr:write("bad login\n")
  unistd.sleep(3)
end
