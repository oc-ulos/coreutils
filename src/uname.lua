#!/usr/bin/env lua
-- uname

local argv = {...}

local fields = {}

for k,v in pairs {"sysname", "nodename", "release", "version", "machine"} do
  fields[k] = v
  fields[v] = false
end

local uname = require("posix.sys.utsname").uname()

if #argv == 0 then argv[1] = "-s" end

for i=1, #argv, 1 do
  local a = argv[i]

  if a == "-a" or a == "--all" then
    for k in pairs(fields) do
      if type(k) ~= "number" then fields[k] = true end
    end
    break

  elseif a == "-s" or a == "--kernel-name" then
    fields.sysname = true

  elseif a == "-n" or a == "--nodename" then
    fields.nodename = true

  elseif a == "-r" or a == "--kernel-release" then
    fields.release = true

  elseif a == "-v" or a == "--kernel-version" then
    fields.version = true

  elseif a == "-m" or a == "--machine" then
    fields.machine = true

  elseif a == "--help" then
    io.stderr:write([[
usage: uname [OPTION]...
Print certain system information.  With no OPTION, behave like -s.

Fields are printed in the order they are listed here, skipping those that are
not enabled.

  -a, --all             enable all fields
  -s, --kernel-name     the name of the kernel
  -n, --nodename        the hostname
  -r, --kernel-release  the kernel release
  -v, --kernel-version  the kernel version
  -m, --machine         the machine type
      --help            show this help message and exit

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
    os.exit(0)

  else
    io.stderr:write("uname: invalid option\nsee 'uname --help' for more information.\n")
    os.exit(1)
  end
end

local final = {}

for i=1, #fields, 1 do
  if fields[fields[i]] then
    final[#final+1] = uname[fields[i]]
  end
end

print(table.concat(final, " "))
