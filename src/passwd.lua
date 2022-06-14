--!lua

local argv = ...

local help = ([[
usage: %s [options] [LOGIN]

options:
  -h, --help      show this help message
  -l, --lock      set the given account to locked
  -u, --unlock    set the given account to unlocked

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(argv[0])

local args, opts = require("getopt").getopt({
  options = {
    h = false, help = false,
    l = false, lock = false,
    u = false, unlock = false
  },
  finish_after_arg = true,
  exit_on_bad_opt = true,
  help_message = help
}, argv)

opts.l = opts.l or opts.lock
opts.u = opts.u or opts.unlock

if opts.h or opts.help or (opts.l and opts.u) then
  io.stderr:write(help)
  os.exit(1)
end

local pwd = require("posix.pwd")
local ioctl = require("syscalls").ioctl
local unistd = require("posix.unistd")

local login
if args[1] then
  login = pwd.getpwnam(args[1])
else
  login = pwd.getpwuid(unistd.getuid())
end

if not login then
  if args[1] then
    io.stderr:write("user '", args[1], "' not found\n")
  else
    io.stderr:write("could not get current user\n")
  end
  os.exit(1)
end

local function getpasswd(prompt)
  io.stdout:write(prompt)
  ioctl(0, "stty", {echo = false})
  local password = io.stdin:read("l")
  ioctl(0, "stty", {echo = true})
  io.stdout:write("\n")
  return password
end

if opts.l then
  if login.pw_passwd:sub(1,1) ~= "!" then
    login.pw_passwd = "!" .. login.pw_passwd
  end

elseif opts.u then
  if login.pw_passwd:sub(1,1) == "!" then
    login.pw_passwd = login.pw_passwd:sub(2)
  end

else
  if #login.pw_passwd > 0 and unistd.getuid() > 0 then
    local old = getpasswd("old password for "..login.pw_name..": ")
    if unistd.crypt(old) ~= login.pw_passwd then
      unistd.sleep(3)
      io.stderr:write("bad login\n")
      os.exit(1)
    end
  end

  local password = getpasswd("new password for "..login.pw_name..": ")
  local password2 = getpasswd("confirm new password: ")
  if password ~= password2 then
    io.stderr:write("passwords are mismatched\n")
    os.exit(1)
  end
  login.pw_passwd = unistd.crypt(password)
end

pwd.update_passwd(login)
