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

The SPEC given to -p must be of the format N:a=b,c=d;N2:a=e,c=f where
N and N2 are partition IDs and others are options.

partition options:
  --required--
  type=TYPE     set the partition type.  May be either a string or a number.
  --optional--
  size=N        set the partition size.  A suffix of s indicates size in
                sectors, otherwise size is in KiB (1024).  Unused space is
                divided evenly among partitions with no defined size.
  label=LABEL   set the partition label, if not given set to e.g. 'osdi1'

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(1)
end

if #args == 0 then showusage() end

local count = opts.c or 0
local spec = opts.p
if not spec then
  io.stderr:write("mkpart: warning: no partition spec provided, creating blank table\n")
  spec = {}
else
  local _spec = {}
  local maxid = 0
  if spec:sub(-1) ~= ";" then spec = spec .. ";" end
  for id, entry in spec:gmatch("(%d+):([^;]+);") do
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
  spec = _spec
end

-- TODO: support mtpt as well
local parttable = ""
local sectorsize = tonumber(opts.s) or 512
local magic = "OSDI\xAA\xAA\x55\x55"
local pack_format = "<I4I4c8c3c13"
local label = opts.l or "osdi-"..math.floor(math.random(10000000,99999999))
parttable = parttable .. pack_format:pack(1, 0, magic, "", label)
local offset = 1
local totalSize = 0
local undefinedSize = 0

for i=1, #spec do
  local spec = spec[i]
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
    spec.size = spec.size * sectorsize
    totalSize = totalSize + spec.size
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

for i=1, #spec do
  local spec = spec[i]
  if not spec.size then
    spec.size = math.floor((size-totalSize)/undefinedSize)
    io.stderr:write("mkpart: assigned size ", spec.size/2, "K to partition ", i, "\n")
  end
  local label = spec.label or "osdi"..i
  local start = offset
  offset = offset + spec.size
  parttable = parttable .. pack_format:pack(
    start, spec.size, spec.type, "", label)
end

if #parttable > sectorsize then
  io.stderr:write(("mkpart: partition table too long: %d vs sector size %d\n")
    :format(#parttable, sectorsize))
  os.exit(1)
end

hand:seek("set")
hand:write(parttable)

io.stderr:write("mkpart: telling kernel to reread partition table\n")
local ok, err = require("syscalls").ioctl(require("posix.stdio").fileno(hand), "reregister")
if not ok then
  io.stderr:write("mkpart: WARNING: reregister failed: ", require("posix.errno").errno(err), "\n")
  io.stderr:write("you may need to restart for partition table changes to take effect\n")
end

hand:close()
