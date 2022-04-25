--!lua
local argv = ...

local stat = require("posix.sys.stat")
local errno = require("posix.errno")
local unistd = require("posix.unistd")
local args, opts = require("getopt").getopt({
  options = {
    f = false, force = false,
    i = false, r = false,
    R = false, recursive = false,
    v = false, verbose = false,
    help = false,
  },
  allow_finish = true,
  exit_on_bad_opt = true,
  help_message = "see '" .. argv[0] .. " --help' for more information.\n"
}, argv)

opts.f = opts.f or opts.force
opts.r = opts.r or opts.R or opts.recursive
opts.v = opts.v or opts.verbose

if opts.help then
  io.stderr:write(([[
usage: %s [OPTION]... [FILE]...
Remove (unlink) the specified FILE(s).

  -f, --force         Ignore failures, never prompt (overrides -i)
  -i                  Prompt before every removal
  -r, -R, --recursive Recursively remove directories
  -v, --verbose       Be verbose
  --help              Show this help message

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(argv[0]))
end

if #args == 0 then
  io.stderr:write(argv[0] .. ": missing operand\n",
    "see '" .. argv[0] .. " --help' for more information.\n")
  os.exit(1)
end

local function rm(file)
  local success, err = unistd.unlink(file)
  local dir = false

  if err == errno.EISDIR and opts.r then
    dir = true
    success, err = unistd.rmdir(file)
    if err == errno.EEXIST then
      for _file in dirent.files(file) do
        rm(file.."/".._file)
      end
    end
  end

  if not (success or opts.f) then
    io.stderr:write(argv[0], ": cannot remove '", file, "': ",
      errno.errno(err), "\n")
    os.exit(1)
  end

  if opts.v and success then
    io.write("removed ", dir and "directory '" or "'", file, "'\n")
  end
end

for i=1, #args, 1 do
  if args[i] == "/" then
    io.stderr:write(argv[0], ": refusing to remove '/'\n")
    os.exit(1)
  end
  rm(args[i])
end
