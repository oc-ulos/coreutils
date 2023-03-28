#!/usr/bin/env lua

local stat = require("posix.sys.stat")
local sizes = require("sizes")
local getopt = require("getopt")
local dirent = require("posix.dirent")

local args, opts, usage = getopt.process {
  {"end each output line with NUL, not newline", false, "0", "null"},
  {"write sizes for each file, not just directories", false, "a", "all"},
  {"show apparent sizes rather than filesystem space usage", false, "apparent"},
  {"produce a grand total", false, "c", "total"},
  {"print sizes in human readable format", false, "h", "human-readable"},
  {"like -h, but use powers of 1000, not 1024", false, "si"},
  {"display only a total for each argument", false, "s", "summarize"},
  {"exclude entries larger than SIZE if positive, or greater than SIZE if negative", "SIZE", "t", "threshold"},
  {"exclude files that match any pattern in FILE", "FILE", "X", "exclude-from"},
  {"exclude files that match PATTERN", "PATTERN", "exclude"},
  {"display this help and exit", false, "help"},
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help\n",
  args = arg,
}

if opts.help then
  io.stderr:write(([[
usage: du [options] [file ...]
Summarize space usage of the given files, recursing into directories.

%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(0)
end

local delim = opts["0"] and "\0" or "\n"

local function summarize(path)
  local info = stat.stat(path)
  -- this may not be the most accurate way to do it, but i'm doing it anyway
  local total = (opts.apparent and info.st_size)
    or (info.st_blocks * info.st_blksize)
  if stat.S_ISDIR(info.st_mode) ~= 0 then
    for file in dirent.files(path) do
      if file ~= "." and file ~= ".." then
        total = total + summarize(path.."/"..file)
      end
    end
  end

  -- display output
  local size
  if opts.h then size = sizes.format(total) else size = tostring(total) end
  if stat.S_ISDIR(info.st_mode) ~= 0 or opts.a then
    io.write(size .. "\t" .. path .. delim)
  end
  return total
end

if not args[1] then args[1] = "." end
local grandTotal = 0
for i=1, #args do
  grandTotal = grandTotal + summarize(args[i])
end

if opts.c then
  local size = opts.h and sizes.format(grandTotal) or tostring(grandTotal)
  io.write(size .. "\ttotal" .. delim)
end
