#!/usr/bin/env lua
-- free

local args, opts, usage = require("getopt").process {
  { "Display this help message", false, "help" },
  { "Output in kibibytes", false, "k", "kibi", "kilo" },
  { "Output in mebibytes", false, "m", "mebi", "mega" },
  { "Use powers of 1000, not 1024", false, "si" },
  { "Human-readable output (like -k)", false, "h", "human" },
  { "Repeat every N seconds", "N", "s", "seconds" },
  { "Repeat N times, then exit", "N", "c", "count"},
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help\n",
  args = arg
}

if #args > 0 or opts.h then
  io.stderr:write(([[
usage: free [options]

options:
%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3
]]):format(usage))
  os.exit(1)
end

local total, free, used = 0, 0, 0
local hand, err = io.open("/proc/meminfo", "r")
if not hand then
  io.stderr:write("could not open /proc/meminfo: ", err, "\n")
  os.exit(1)
  -- good god LSP, is `os.exit()` not good enough?
  error()
end

for line in hand:lines() do
  if line:match("MemTotal") then
    total = tonumber((line:match("(%d+) kB"))) * 1024
  elseif line:match("MemAvailable") then
    free = tonumber((line:match("(%d+) kB"))) * 1024
  elseif line:match("MemUsed") then
    used = tonumber((line:match("(%d+) kB"))) * 1024
  end
end

hand:close()

-- some systems (i.e. Linux) don't provide this
if used == 0 then used = total - free end

local power = opts.si and 1000 or 1024
local suffix = opts.si and "" or "b"

if opts.h or opts.k or not next(opts) then
  total = string.format("%.1f", total / power) .. " K" .. suffix
  used = string.format("%.1f", used / power) .. " K" .. suffix
  free = string.format("%.1f", free / power) .. "K" .. suffix
elseif opts.m then
  total = string.format("%.1f", total / power / power) .. " M" .. suffix
  used = string.format("%.1f", used / power / power) .. " M" .. suffix
  free = string.format("%.1f", free / power / power) .. " M" .. suffix
end

io.write("  total    /    used    /    free\n")
io.write(("%10s / %10s / %10s\n"):format(total, used, free))
