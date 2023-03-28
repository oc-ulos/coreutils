#!/usr/bin/env lua

local stat = require("posix.sys.stat")
local sizes = require("sizes")
local getopt = require("getopt")
local stdlib = require("posix.stdlib")
local treeutil = require("treeutil")

local args, opts, usage = getopt.process {
  {"end each output line with NUL, not newline", false, "0", "null"},
  {"write sizes for each file, not just directories", false, "a", "all"},
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

local grand_total = 0
local delim = opts["0"] and "\0" or "\n"

local function foreach(file, info)
  local size = info.st_size
  local total = size
  if stat.S_ISDIR(info.st_mode) ~= 0 then
    total = total + -- TODO TODO TODO TODO
    treeutil.tree(file, nil, foreach)
  end

  -- display output
  if opts.h then size = sizes.format(size) else size = tostring(size) end
  if stat.S_ISDIR(info.st_mode) ~= 0 or opts.a then
    io.write(total .. "\t" .. file .. delim)
  end
  grand_total = grand_total + total
  currentTotal = total
  -- hack: stop recursion
  info.st_mode = -1
end

if not args[1] then args[1] = "." end
for i=1, #args do
  treeutil.tree(args[i], nil, foreach)
end
