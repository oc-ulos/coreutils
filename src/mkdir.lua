--!lua
local argv = ...

local errno = require("posix.errno")
local stat = require("posix.sys.stat")
local libgen = require("posix.libgen")

local args, opts = require("getopt").getopt({
  options = {
    p = false, parents = false,
    m = true, mode = true,
    help = false
  },
  exit_on_bad_opt = true,
  allow_finish = true,
  help_message = "see '" .. argv[0] .. " --help' for more information\n"
}, argv)

if opts.help then
  io.stderr:write([[
usage: ]]..argv[0]..[[ [OPTION]... DIRECTORY...
Create DIRECTORY(ies) if they do not exist.

  -m, --mode MODE   Set file mode. MODE must be a number.
  -p, --parents     Silently create parent directories if necessary, and do
                    not exit on EEXIST
      --help        Print this help message

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
  os.exit(0)
end

if #args == 0 then
  io.stderr:write(argv[0]..[[: missing operand
see ']]..argv[0]..[[ --help' for more information.
]])
  os.exit(1)
end

opts.m = tonumber(opts.m or opts.mode)

for i=1, #args, 1 do
  local arg = args[i]
  local dirname = libgen.dirname(arg)
  if opts.p or opts.parents then
    local path = ""
    for segment in dirname:gmatch("[^/\\]+") do
      path = path .. segment .. "/"
      local success, _, err = stat.mkdir(path, 0x1A4)
      if not success and err ~= errno.EEXIST then
        io.stderr:write(argv[0], ": failed creating parent: ",
          errno.errno(err), "\n")
        os.exit(1)
      end
    end
  end

  local success, err = stat.mkdir(arg, opts.m or 0x1FF)
  if opts.p and err == errno.EXIST then success = true end
  if not success then
    io.stderr:write(argv[0]..": "..errno.errno(err).."\n")
    os.exit(1)
  end
end
