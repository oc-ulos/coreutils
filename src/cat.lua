--!lua

local sys = require("syscalls")
local argv = ...

local args, opts = require("getopt").getopt({
  options = {
    h = false, help = false,
  },
  finish_after_arg = true,
  exit_on_bad_opt = true,
  help_message = "see '"..argv[0].." --help' for more information\n"
}, argv)

if opts.help then
  local t = "\t"
  io.stderr:write([[
Usage: ]]..argv[0]..[[ [OPTION]... [FILE]...
Concatenate one or more FILEs (or standard input) to standard output.  With no
FILE, or when FILE is -, read standard input.

  -h, --help]]..t..[[Print this help message.

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
  sys.exit(1)
end

for i=1, #args do
  local path = args[i]
  local fd, err
  if args[i] == "-" then
    fd = io.stdin
  else
    fd, err = io.open(path, "r")
  end
  if fd then
    -- read data in chunks for memory usage reasons
    repeat
      local data = fd:read(4096)
      if data then io.write(data) end
    until not data
    fd:close()
  else
    io.stderr:write(string.format("%s: %s: %s\n",
      argv[0], path, err))
  end
end

sys.exit(0)
