#!/usr/bin/env lua
-- df

local getopt = require("getopt")
local sizes = require("sizes")

local args, opts, usage = getopt.process {
  { "print sizes in powers of 1024", false, "h", "human-readable" },
  { "print sizes in powers of 1000", false, "H", "si" },
  { "use POSIX output format", false, "P", "portability" },
  { "only show filesystem types matching TYPE", "TYPE", "t", "type" },
  { "print filesystem type", false, "T", "print-type" },
  { "exclude filesystem types matching TYPE", "TYPE", "x", "exclude-type" },
  { "display this help message and exit", false, "help" },
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help\n",
  args = arg,
}

if opts.help then
  io.stderr:write(([[
usage: df [options ...]
Show information about all registered file systems.

options:
%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(0)
end

local columns = {
  {"Filesystem"},
  {opts.h and "Size" or opts.P and "1024-blocks" or "1K-blocks"},
  {"Used"},
  {"Available"},
  {opts.P and "Capacity" or "Use%"},
  {"Mounted on"}}

local mounts = {}
for line in io.lines("/proc/mounts") do
  local addr, path = line:match("([^ ]+) ([^ ]+)")
  if addr and path then
    mounts[addr] = path
  end
end

local component = require("component")
-- TODO: generalize this for drive components?
for addr in component.list("filesystem") do
  local proxy = component.proxy(addr)
  local used, total = proxy.spaceUsed(), proxy.spaceTotal()
  local free = total - used
  local label = proxy.getLabel() or addr:sub(1,8)
  table.insert(columns[1], label)
  table.insert(columns[5], math.ceil((used/total)*100).."%")
  if opts.h then
    used, total, free
      = sizes.format(used), sizes.format(total), sizes.format(free)
  else
    used, total, free =
      math.ceil(used/1024),
      math.ceil(total/1024),
      math.ceil(free/1024)
  end
  table.insert(columns[2], tostring(total))
  table.insert(columns[3], tostring(used))
  table.insert(columns[4], tostring(free))
  table.insert(columns[6], mounts[label] or "?")
end

local widths = {}
for i=1, #columns do
  widths[i] = 0
  for j=1, #columns[i] do
    widths[i] = math.max(widths[i], #columns[i][j] + 1)
  end
end

for i=1, #columns[1] do
  for j=1, #columns do
    local item = columns[j][i]
    if item then item = item .. (" "):rep(widths[j] - #item) end
    io.write(item)
  end
  io.write("\n")
end
