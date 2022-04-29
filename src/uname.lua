--#!/usr/bin/env lua
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
    io.stderr:write()
  else
    io.stderr:write("")
  end
end

local final = {}

for i=1, #fields, 1 do
  if fields[fields[i]] then
    final[#final+1] = uname[fields[i]]
  end
end

print(table.concat(final, " "))
