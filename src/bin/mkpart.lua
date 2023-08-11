--!lua
-- mkpart - write disk partition tables
-- currently only supports OSDI

local args, opts, usage = require("getopt").process {
  {"Number of partitions", "N", "c", "count"},
  {"Whole disk label", "LABEL", "l", "label"},
  {"Set partition properties", "SPEC", "p", "partition", "spec"},
  {"Specify non-standard sector size", "BYTES", "s", "sector-size"},
  {"Do not prompt about partition erasure", "f", "force"},
  {"Show this help and exit", false, "h", "help"},
  help_message = "pass '--help' for help\n",
  exit_on_bad_opt = true,
  args = ...
}

local function showusage()
  io.stderr:write(([[
usage: mkpart VOLUME
Create an OSDI partition table on VOLUME.

options:
%s

The SPEC given to -p must be of the format N:a=b,c=d:N2:a=e,c=f where
N and N2 are partition IDs and others are options.

partition options:
  --required--
  type=TYPE     set the partition type.  May be either a string or a number.
  --optional--
  size=N        set the partition size.  A suffix of s indicates size in
                sectors, otherwise size is in KiB (1024).  Unused space is
                divided evenly among partitions with no defined size.
  label=LABEL   set the partition label, if not given set to e.g. 'osdi1'
  flags=A|B...  set partition flags

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(1)
end

if #args == 0 then showusage() end

local count = opts.c or 0
local specs = opts.p
if not specs then
  io.stderr:write("mkpart: warning: no partition spec provided, creating blank table\n")
  specs = {}
else
  local _spec = {}
  local maxid = 0
  if specs:sub(-1) ~= ":" then specs = specs .. ":" end
  for id, entry in specs:gmatch("(%d+):([^:]+):") do
    id = tonumber(id)
    maxid = math.max(id, maxid)
    local sopts = {}
    for key, val in entry:gmatch("([^=]+)=([^,]+),?") do
      sopts[key] = tonumber(val) or val
    end
    _spec[id] = sopts
  end
  if maxid ~= #_spec then
    io.stderr:write("mkpart: invalid spec: non-continuous partition IDs\n")
    os.exit(1)
  end
  specs = _spec
end

-- TODO: support mtpt as well
local parttable = ""
local sectorsize = tonumber(opts.s) or 512
local magic = "OSDI\xAA\xAA\x55\x55"
local pack_format = "<I4I4c8I3c13"
local label = opts.l or "osdi-"..math.floor(math.random(10000000,99999999))
parttable = parttable .. pack_format:pack(1, 0, magic, 0, label)
local offset = 1
local totalSize = 0
local undefinedSize = 0
local partflags = {active=0x200}

for i=1, #specs do
  local spec = specs[i]
  if not spec.type then
    io.stderr:write("mkpart: partition ", i, " is missing partition type\n")
    os.exit(2)
  end
  if not spec.size then
    undefinedSize = undefinedSize + 1
  end
  if type(spec.size) == "string" then
    if spec.size:sub(-1) == "s" then
      spec.size = tonumber(spec.size:sub(1,-2))
    else
      io.stderr:write("mkpart: partition ", i, " has invalid partition size\n")
      os.exit(2)
    end
  elseif spec.size then
    spec.size = spec.size * 2
    totalSize = totalSize + spec.size
  end
  if spec.flags then
    local flags = 0
    for flag in spec.flags:gmatch("[^|]+") do
      flags = flags | (partflags[flag] or 0)
    end
    spec.flags = flags
  else
    spec.flags = 0
  end
end

if not opts.f then
  io.stderr:write("REALLY overwrite device ", args[1], "? [y/N] ")
  if io.read():lower() ~= "y" then
    io.stderr:write("mkpart: not writing partition table\n")
    os.exit(1)
  end
end

-- TODO: check for existing partition table
local hand, err = io.open(args[1], "w")
if not hand then
  io.stderr:write("mkpart: cannot open ", args[1], ": ", err, "\n")
  os.exit(1)
end

local size = hand:seek("end")/sectorsize - 1

for i=1, #specs do
  local spec = specs[i]
  if not spec.size then
    spec.size = math.floor((size-totalSize)/undefinedSize)
  end
  local label = spec.label or "osdi"..i
  io.stderr:write("mkpart: partition '", label, "' size=", spec.size/2, "K\n")
  local start = offset
  offset = offset + spec.size
  parttable = parttable .. pack_format:pack(
    start, spec.size, spec.type, spec.flags, label)
end

if #parttable > sectorsize then
  io.stderr:write(("mkpart: partition table too long: %d vs sector size %d\n")
    :format(#parttable, sectorsize))
  os.exit(1)
end

hand:seek("set")
hand:write(parttable)
hand:close()

local sys = require("syscalls")
local fd = sys.open(args[1], "r")
io.stderr:write("mkpart: telling kernel to reread partition table\n")
local ok, err = sys.ioctl(fd, "reregister")
if not ok then
  io.stderr:write("mkpart: WARNING: reregister failed: ", require("posix.errno").errno(err), "\n")
  io.stderr:write("you may need to restart for partition table changes to take effect\n")
end

sys.close(fd)
