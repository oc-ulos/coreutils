--!lua
-- a sudo implementation
-- TODO TODO TODO: something like /etc/sudoers?

local sys = require("syscalls")
local pwd = require("posix.pwd")
local grp = require("posix.grp")
local wait = require("posix.sys.wait")
local getopt = require("getopt")
local libgen = require("posix.libgen")
local stdlib = require("posix.stdlib")
local unistd = require("posix.unistd")

local args, opts, usage = getopt.process {
  {"change working directory before running command", "DIR", "D", "chdir"},
  {"edit files rather than running a command", false, "e", "edit"},
  {"act as specified group (name or ID)", "GROUP", "g", "group"},
  {"set HOME variable to target user's home directory", false, "H", "set-home"},
  {"run a login shell as the target user", false, "i", "login"},
  {"chroot before running command", "DIR", "R", "chroot"},
  {"run a shell as the target user", false, "s", "shell"},
  {"act as specified user (name or ID)", "USER", "u", "user"},
  {"display this help message", false, "h", "help"},
  exit_on_bad_opt = true,
  allow_finish = true,
  finish_after_arg = true,
  help_message = "pass '--help' for help\n",
  args = ...
}

if opts.h then
  io.stderr:write(([[
usage: sudo [options ...] [--] [command ...]
Perform an action as another user (default root).

%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(0)
end

if #args == 0 and not (opts.i or opts.s) then
  io.stderr:write("sudo: no arguments provided, exiting\n")
  os.exit(1)
end

if sys.geteuid() ~= 0 then
  io.stderr:write("sudo: cannot run as non-root user\n")
  os.exit(1)
end

if not unistd.isatty(0) or not unistd.isatty(1) then
  io.stderr:write("sudo: refusing to run because stdin/stdout are not TTYs\n")
  os.exit(1)
end

io.stdin:flush()

if opts.i and opts.s then
  io.stderr:write("sudo: you may not specify both -i and -s")
  os.exit(1)
end

-- get username and uid
local name = tonumber(opts.u or "") or opts.u or "root"
local uid
-- can i have your name and number please?
if type(name) == "number" then uid = name; name = nil end
local pwent
if name then
  pwent = pwd.getpwnam(name)
else
  pwent = pwd.getpwuid(uid)
end
if not pwent then
  io.stderr:write("sudo: unknown user " .. (name or uid) .. "\n")
  os.exit(2)
end
name, uid = name or pwent.pw_name, uid or pwent.pw_uid

-- get group name and gid
local group = tonumber(opts.g or "") or opts.g or pwent.pw_gid or "root"
local gid
if type(group) == "number" then gid = group; group = nil end
local grent
if group then
  grent = grp.getgrnam(group)
else
  grent = grp.getgrgid(gid)
end
if not grent then
  io.stderr:write("sudo: unknown group " .. (group or gid) .. "\n")
  os.exit(2)
end
group, gid = group or grent.gr_name, gid or grent.gr_gid

-- read and verify password for the invoking user
local original_uid = sys.getuid()
local oent = pwd.getpwuid(original_uid)
io.stdout:write("[sudo] password for " .. oent.pw_name .. ": ")
sys.ioctl(0, "stty", {echo = false})
local input = io.stdin:read("l")
local password = unistd.crypt(input)
sys.ioctl(0, "stty", {echo = true})
io.stdout:write("\n")

local function act(func)
  local pid = sys.fork(function()
    sys.setuid(uid)
    sys.setgid(gid)
    sys.setsid()
    if opts.H then
      stdlib.setenv("HOME", pwent.pw_dir or "/")
    end
    if opts.R then
      local ok, err = sys.chroot(opts.R)
      if not ok then
        io.stderr:write("sudo: chroot: " .. err .. "\n")
        os.exit(1)
      end
    end
    stdlib.setenv("USER", pwent.pw_name)
    stdlib.setenv("HOME", pwent.pw_dir or "/")
    stdlib.setenv("UID", tostring(pwent.pw_uid))
    stdlib.setenv("GID", tostring(pwent.pw_gid))
    stdlib.setenv("SHELL", pwent.pw_shell or "/bin/sh.lua")
    local result, err = func()
    if not result and err then
      io.stderr:write("sudo: ", tostring(err), "\n")
      os.exit(1)
    end
    os.exit(0)
  end)
  local _, _, status = wait.wait(pid)
  os.exit(status)
end

local function copy(a,b)
  local inh, ie = io.open(a, "r")
  if not inh then
    io.stderr:write("sudo: ", ie, "\n")
    return os.exit(3)
  end
  local out, oe = io.open(b, "w")
  if not out then
    inh:close()
    io.stderr:write("sudo: ", oe, "\n")
    return os.exit(3)
  end
  for line in inh:lines() do
    out:write(line)
  end
  inh:close()
  out:close()
end

if password == oent.pw_passwd then
  if opts.i then
    act(function()
      unistd.execp(pwent.pw_shell or "/bin/sh.lua", {"--login"})
    end)
  elseif opts.s then
    act(function()
      unistd.execp(pwent.pw_shell or "/bin/sh.lua", {})
    end)
  elseif opts.e then
    local editor =
          os.getenv("SUDO_EDITOR")
      or os.getenv("VISUAL")
      or os.getenv("EDITOR")
      or "/bin/edit.lua"

    for i=1, #args do
      local base = libgen.basename(args[i])
      local tmp = "/tmp/"..base..".tmp."..math.random(1000,9999)
      copy(args[i], tmp)
      act(function()
        local result, err = unistd.execp(editor, {tmp})
        if not result then
          io.stderr:write("sudo: invoke ", editor, ": ", err, "\n")
          os.exit(1)
        end
      end)

      act(function()
        -- TODO: can we move this instead of copying it? for atomicity
        copy(tmp, args[i])
      end)
      os.remove(tmp)
    end
  else
    act(function()
      unistd.execp(args[1], {table.unpack(args, 2)})
    end)
  end
else
  unistd.sleep(3)
  io.stderr:write("sudo: bad credentials\n")
  os.exit(2)
end
