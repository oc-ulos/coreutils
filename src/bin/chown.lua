#!/usr/bin/env lua
-- chown implementation

local getopt = require("getopt")
local stdlib = require("posix.stdlib")
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local tree = require("treeutil")
local pwd = require("posix.pwd")
local grp = require("posix.grp")

local options, usage, condense = getopt.build {
  { "Display this help message", false, "h", "help" },
  { "Output a message for every file processed",  false, "v", "verbose" },
  { "Suppress error messages", false, "s", "silent", "quiet" },
  { "Recurse into subdirectories", false, "R", "recursive" },
}

local args, opts = getopt.getopt({
  options = options,
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help"
}, {...})

condense(opts)

local function showusage()
  io.stderr:write(string.format([[
usage: chown [OPTION]... [OWNER][:GROUP] FILE...

options:
%s

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]], usage))
  os.exit(1)
end

if opts.h or #args == 0 then
  showusage()
end

local owner, group = args[1], ""
if owner:find(":") then
  local newOwn, newGroup = owner:match("(.*):(.*)")
  if newOwn and newGroup then
    owner, group = newOwn, newGroup
  else
    io.stderr:write("chown: cannot parse '", owner, "'\n")
    os.exit(1)
  end
end

local ownerID = pwd.getpwnam(owner)
if #owner > 0 and not ownerID then
  io.stderr:write("chown: ", owner, ": user not found\n")
  os.exit(1)
end

local groupID = grp.getgrnam(group)
if #group > 0 and not groupID then
  io.stderr:write("chown: ", group, ": group not found\n")
  os.exit(1)

elseif ownerID and not groupID then
  groupID = ownerID.pw_gid

else
  groupID = groupID.gr_gid
end

if ownerID then
  ownerID = ownerID.pw_uid
end

local function chown(file)
  local absolute, err = stdlib.realpath(file)
  if absolute then
    local info = stat.stat(absolute)
    local oid, gid = ownerID, groupID

    if not (oid and gid) then
      oid = oid or info.st_uid
      gid = gid or info.st_gid
    end

    if stat.S_ISDIR(info.st_mode) == 1 and opts.R then
      tree.tree(absolute, nil, chown)
    end

    if opts.v then
      print(file)
    end

    unistd.chown(absolute, oid, gid)

  elseif not opts.s then
    io.stderr:write("chown: ", file, ": ", err, "\n")
    os.exit(1)
  end
end

for i=2, #args, 1 do
  chown(args[i])
end
