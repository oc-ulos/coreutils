#!/usr/bin/env lua
-- cp implementation

local tree = require("treeutil").tree
local getopt = require("getopt")
local libgen = require("posix.libgen")
local stdlib = require("posix.stdlib")
local stat = require("posix.sys.stat")

local options, usage, condense = getopt.build {
  { "Display this help message", false, "h", "help" },
  { "Suppress error messages", false, "f", "force" },
  { "Recurse into directories", false, "R", "r", "recursive" },
  { "Be verbose", false, "v", "verbose" }
}

local args, opts = getopt.getopt({
  options = options,
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help"
}, {...})

condense(opts)

local function showusage()
  io.stderr:write(([[
usage: cp [OPTION]... FILE... DEST
Copy one or more FILE(s) to DEST.  If multiple FILEs are specified, DEST must
be a directory.

options:
%s

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(1)
end

if #args < 2 or opts.h then
  showusage()
end

local function copy(src, dest)
  if opts.v then
    print(string.format("'%s' -> '%s'", src, dest))
  end

  local inhandle, err1 = io.open(src, "r")
  if not inhandle then
    return nil, src .. ": " .. err1
  end

  local outhandle, err2 = io.open(dest, "w")
  if not outhandle then
    return nil, dest .. ": " .. err2
  end

  repeat
    local data = inhandle:read(8192)
    if data then outhandle:write(data) end
  until not data

  inhandle:close()
  outhandle:close()

  return true
end

local function exit(...)
  io.stderr:write("cp: ", ...)
  os.exit(1)
end

local destIsDir
local dest, derr = stdlib.realpath(args[#args])

if #args > 2 and not dest then
  exit(args[#args], ": ", derr, "\n")
end

if dest then
  local dstat = stat.stat(dest)
  destIsDir = dstat and (stat.S_ISDIR(dstat.st_mode) == 1)

else
  dest = args[#args]
end

args[#args] = nil

if #args > 1 and not destIsDir then
  exit("cannot copy to '", dest, "': target is not a directory\n")
end

local function tryMkdir(f)
  local ok, err = stat.mkdir(f, 511)
  if not ok then
    exit("cannot create directory ", f, ": ", err, "\n")
  end
end

local function cp(f)
  local file, rerr = stdlib.realpath(f)

  if not file then
    exit("cp: cannot resolve '", f, "': ", rerr, "\n")
  end

  local statx = stat.stat(file)

  if stat.S_ISDIR(statx.st_mode) == 1 then
    if not opts.R then
      exit("cannot copy directory '", f, "'; use -r to recurse\n")
    end

    tryMkdir(dest)

    tree(file, nil, function(thing)
      local new = (dest .. "/" .. thing:sub(#file + 1)):gsub("/+", "/")
      local tstatx = stat.stat(thing)

      if stat.S_ISDIR(tstatx.st_mode) == 1 then
        tryMkdir(new)

      else
        local ok, err = copy(thing, new)
        if not ok then exit(err, "\n") end
      end
    end)

  else
    local dst = dest
    if #args > 1 or destIsDir then
      dst = (dst .. "/" .. libgen.basename(file)):gsub("/+", "/")
    end

    local ok, err = copy(file, dst)
    if not ok then exit(err, "\n") end
  end
end

for i=1, #args, 1 do cp(args[i]) end
