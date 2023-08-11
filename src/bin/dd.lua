--!lua
-- dd - copy files to other files

local stat = require("posix.sys.stat")

local args, opts, usage = require("getopt").process {
  {"Show this help message", false, "h", "help"},
  {"Block size in bytes", "BS", "b", "bs", "blocksize"},
  {"Number of blocks to copy", "N", "c", "count"},
  {"Display information", false, "s", "status", "show-status"},
  exit_on_bad_opt = true,
  allow_finish = true,
  args = ...
}

args[2] = args[2] or "-"
args[1] = args[1] or "-"

if opts.h then
  io.stderr:write(([[
usage: dd [input] [output]
Copy a file.

options:
%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(1)
end

local input, output, isize
if args[1] == "-" then
  input = io.stdin
  isize = 0
else
  local sx, err = stat.stat(args[1])
  if not sx then
    io.stderr:write("dd: ", args[1], ": ", err, "\n")
    os.exit(1)
  end
  isize = sx.st_size

  local err
  input, err = io.open(args[1], "rb")
  if not input then
    io.stderr:write("dd: ", args[1], ": ", err, "\n")
    os.exit(1)
  end
end
if args[2] == "-" then
  output = io.stdout
else
  local err
  output, err = io.open(args[2], "wb")
  if not output then
    io.stderr:write("dd: ", args[2], ": ", err, "\n")
    os.exit(1)
  end
end
opts.b = tonumber(opts.b) or 512
opts.c = tonumber(opts.c) or math.huge
if isize == 0 then isize = opts.c*opts.b end

local written = 0
local blocksWritten = 0
repeat
  local block = input:read(opts.b)
  if block then
    output:write(block)
    written = written + #block
    blocksWritten = blocksWritten + 1
    isize = math.max(isize or 0, written)
  end
  if opts.s and blocksWritten % 10 == 0 or blocksWritten == opts.c or not block then
    io.stderr:write(("bytes written: %q/%q\n"):format(written,isize))
  end
until blocksWritten >= opts.c or (not block) or #block == 0

input:close()
output:close()
