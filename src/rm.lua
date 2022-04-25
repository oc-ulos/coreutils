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

if not args[1] then
  io.stderr:write(argv[0] .. ": missing operand\n",
    "see '" .. argv[0] .. " --help' for more information.\n")
  os.exit(1)
end

for i=1, #args, 1 do
  local success, err = unistd.unlink(args[i])
  local dir = false

  if err == errno.EISDIR and opts.r then
    dir = true
    success, err = unistd.rmdir(args[i])
  end

  if not (success or opts.f) then
    io.stderr:write(argv[0], ": cannot remove '", args[i], "': ",
      errno.errno(err), "\n")
    os.exit(1)
  end

  if opts.v and success then
    io.write("removed ", dir and "directory '" or "'", args[i], "'\n")
  end
end
