--!lua

local sys = require("syscalls")
local errno = require("posix.errno")

local options, usage, condense = require("getopt").build {
  { "Clear the kernel ring buffer\t\t",     false,  "C", "clear" },
  { "Print, then clear, the ring buffer\t", false,  "c", "read-clear" },
  { "Set the console log level",            "LEVEL","n", "console-level" },
  { "Enable logging to the console\t",      false,  "E", "console-on" },
  { "Disable logging to the console\t",     false,  "D", "console-off" },
  { "Show this help message\t\t",           false,  "h", "help" },
}

local _, opts = require("getopt").getopt({
  options = options,
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help\n"
}, ...)

condense(opts)

local function showusage()
  io.stderr:write(string.format([[
usage: dmesg [options]

options:
%s

Options are mutually exclusive.

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]], usage))
  os.exit(1)
end

if opts.h or (opts.n and not tonumber(opts.n)) then
  showusage()
end

local nsel = 0 + (opts.C and 1 or 0) + (opts.c and 1 or 0) +
  (opts.n and 1 or 0) + (opts.E and 1 or 0) + (opts.D and 1 or 0)

if nsel > 1 then showusage() end
if nsel == 0 then opts.c = true end

local function do_syslog(...)
  local res, err = sys.syslog(...)
  if not res then
    io.stderr:write(string.format("dmesg: %s\n", errno.errno(err)))
    os.exit(1)
  end

  for i=1, #res, 1 do
    print(res[i])
  end
end

if opts.C then
  do_syslog("clear")

elseif opts.c then
  do_syslog("read_clear")

elseif opts.n then
  do_syslog("console_level", tonumber(opts.n))

elseif opts.E then
  do_syslog("console_on")

elseif opts.D then
  do_syslog("console_off")
end
