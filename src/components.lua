--!lua

local component = require("component")

local args, opts = require("getopt").getopt({options={
  h = false, help = false,
  a = false, address = false,
  d = false, device = false,
}}, ...)

if opts.h or opts.help then
  io.stderr:write([[
usage: components [options]
List components in the system.

options:
  -a, --address   Show component addresses
  -d, --device    Show each component's devfs path
  -h, --help      Show this help message and exit

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]])
  os.exit(0)
end

local entries = {}
local devlen = 0

for address, ctype, device in component.list() do
  devlen = math.max(devlen, #device + 2)
  entries[#entries+1] = {address = address, device = device, type = ctype}
end

devlen = 8 * math.floor((devlen + 9) / 8) - 1

for i=1, #entries, 1 do
  local entry = entries[i]
  local address, device, ctype = entry.address, entry.device, entry.type
  if opts.a or opts.address then
    io.write(address, "\t")
  end
  if opts.d or opts.device then
    io.write(device .. (" "):rep(devlen - #device))
  end
  print(ctype)
end
