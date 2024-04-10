--!lua
-- basic getty implementation

local sys = require("syscalls")
local dirent = require("posix.dirent")
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")

local args, opts, usage = require("getopt").process {
  {"Automatically login a user", "NAME", "a", "autologin"},
  {"Do not display /etc/issue", false, "i", "noissue"},
  {"Do not clear the screen", false, "J", "noclear"},
  {"Do not prompt for a login name", false, "n", "skip-login"},
  {"No newline before printing /etc/issue", false, "N", "nonewline"},
  {"Change root to the given directory", "DIRECTORY", "r", "chroot"},
  {"Wait for CR or LF before printing /etc/issue", "w", "wait-cr"},
  {"Do not show a hostname", false, "nohostname"},
  {"Additional characters to interpret as backspace", "CHARS", "erase-chars"},
  {"Additional kill characters", "CHARS", "kill-chars"},
  {"Sleep for some time before starting", "SECONDS", "delay"},
  {"Show this help message", false, "h", "help"},
  exit_on_bad_opt = true,
  finish_after_arg = true,
  help_message = "pass '--help' for usage information\n",
  args = ...
}

local function showusage()
  io.stderr:write(([[
usage: getty [options] PORT
Prompt for a login name, then invoke /bin/login.

options:
%s

Copyright (c) 2024 ULOS Developers under the GNU GPLv3.
]]))
end

local uname = require("posix.sys.utsname").uname()
local function print_issue(line, tty)
  line = line:gsub("\\%a", {
    ["\\s"] = uname.sysname,
    ["\\l"] = args[1] or "tty1",
    ["\\r"] = uname.release,
    ["\\v"] = uname.version
  })
  if tty then
    sys.write(tty, line.."\n")
  else
    print(line)
  end
end

local function showissue(tty)
  local fd = io.open("/etc/issue", "r")
  if fd then
    for line in fd:lines() do print_issue(line, tty) end
    fd:close()
    if sys.stat("/etc/issue.d") then
      local issues = dirent.dir("/etc/issue.d")
      table.sort(issues)
      for i=1, #issues do
        for line in io.lines("/etc/issue.d/"..issues[i]) do
          print_issue(line, tty)
        end
      end
    end
  end
end

if opts["show-issue"] then
  showissue()
  os.exit(0)
end

local port = args[1]
if not port then
  io.stderr:write("getty: no tty given\n")
  os.exit(1)
end

local tty_fd

if port ~= "-" then
  tty_fd = sys.open("/dev/"..port, "rw")
  if not tty_fd then
    io.stderr:write("getty: failed to open /dev/"..tty.."\n")
    os.exit(1)
  end
end

if not opts.c then
  -- set up the tty
  sys.write(tty_fd, "\27c\27[20h")
end

if not opts.J then
  sys.write(tty_fd, "\27[2J\27[H")
end

sys.flush(tty_fd)

if opts.w then sys.read(tty_fd, "l") end

if not opts.i then
  if not opts.N then
    sys.write(tty_fd, "\n")
  end

  showissue(tty_fd)
end

if not opts.nohostname then
  sys.write(tty_fd, uname.nodename.." ")
end

local login_cmd = {[0] = opts.l or "/bin/login.lua"}
local name
if opts.a then
  name = opts.a
  login_cmd[#login_cmd+1] = "-f"
end

if not opts.n then
  name = ""
  while #name == 0 do
    sys.write(tty_fd, "login: ")
    name = sys.read(tty_fd, "l")
  end
end

-- TODO erase/kill characters
if opts["erase-chars"] then
end

if opts["kill-chars"] then
end

login_cmd[#login_cmd+1] = name

if port ~= "-" then
  -- set tty_fd as stdio
  for i=0, 2 do
    sys.dup2(tty_fd, i)
  end

  sys.close(tty_fd)
end
sys.execve(login_cmd[0], login_cmd)
