#!/usr/bin/env lua
-- slightly non-standard chmod implementation

local getopt = require("getopt")
local perms = require("permissions")
local stat = require("posix.sys.stat")
local stdlib = require("posix.stdlib")
local tree = require("treeutil")

local options, usage, condense = getopt.build {
  { "Display this help message", false, "h", "help" },
  { "Suppress most error messages", false, "f", "silent", "quiet" },
  { "Output a message for every file processed", false, "v", "verbose" },
  { "Like -v, but only when a change is made", false, "c", "changes" },
  { "Recurse into directories", false, "R", "recursive" }
}

local args, opts = getopt.getopt({
  options = options,
  exit_on_bad_opt = true,
  exclude_numbers = true,
  help_message = "pass '--help' for help"
}, {...})

condense(opts)

local function showusage()
  io.stderr:write(string.format([[
usage: chmod [OPTION]... MODE FILE...
Change the mode of each FILE to MODE.

MODE may be:
  - a string rwxrwxrwx, like shown by ls
  - a three-digit octal number 777, like standard
  - a string matching the pattern [ugoa][+-=][rwx], like standard

If prefixed by '+' or '-', then MODE will be added or removed from each FILE's
existing mode respectively.

options:
%s

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]], usage))
  os.exit(1)
end

if opts.h or #args == 0 then
  showusage()
end

local newMode = args[1]
local ar, sub
if newMode:match("^[%+%-%=]") and #newMode == 4 or #newMode == 10 then
  ar = newMode:sub(1, 1)
  newMode = newMode:sub(2)
end

if newMode:match("^[ugoa]?[%+%-%=]?[rwx]") then
  local ugoa, pme, rwx = newMode:match("^([ugoa]?)([%+%-%=]?)([rwx])")
  if (ugoa and not pme) or not rwx then
    io.stderr:write("chmod: bad mode\n")
    os.exit(1)
  end
  ar = pme
  ugoa = #ugoa > 0 and ugoa or "a"
  local r, w, x = rwx:match("(r?)(w?)(x?)")
  r, w, x = #r > 0 and r or "-", #w > 0 and w or "-", #x > 0 and x or "-"
  if ugoa == "u" then sub="u" newMode = r..w..x.."------" end
  if ugoa == "g" then sub="g" newMode = "---"..r..w..x.."---" end
  if ugoa == "o" then sub="o" newMode = "------"..r..w..x end
  if ugoa == "a" then newMode = (r..w..x):rep(3) end
end

if tonumber(newMode) then
  newMode = tonumber(newMode, 8)

else
  newMode = perms.strtobmp(newMode)
end

if type(newMode) == "string" or not newMode then
  io.stderr:write("chmod: ", args[1], ": invalid mode\n")
  os.exit(1)
end

local function chmod(file)
  local absolute, err = stdlib.realpath(file)

  if absolute then
    local info = stat.stat(absolute)
    local oldPerms = info.st_mode & ~stat.S_IFMT
    local newPerms = 0
    local rest = info.st_mode & stat.S_IFMT

    if ar == "+" then
      newPerms = oldPerms | newMode

    elseif ar == "-" then
      newPerms = oldPerms & ~newMode

    else
      if sub == "u" then
        newPerms = (oldPerms & (stat.S_IRWXG | stat.S_IRWXO)) | newMode

      elseif sub == "g" then
        newPerms = (oldPerms & (stat.S_IRWXU | stat.S_IRWXO)) | newMode

      elseif sub == "o" then
        newPerms = (oldPerms & (stat.S_IRWXU | stat.S_IRWXG)) | newMode

      else
        newPerms = newMode
      end
    end

    if (opts.c and oldPerms ~= newPerms) or opts.v then
      print(file)
    end

    if stat.S_ISDIR(rest) == 1 and opts.R then
      tree.tree(absolute, nil, chmod)
    end

    stat.chmod(absolute, rest | newPerms)

  elseif not opts.f then
    io.stderr:write("chmod: ", file, ": ", err, "\n")
    os.exit(1)
  end
end

for i=2, #args, 1 do
  chmod(args[i])
end
