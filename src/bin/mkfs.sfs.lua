--!lua
-- mkfs.sfs - create a SimpleFS formatted volume

local args, opts, usage = require("getopt").process {
  {"Filesystem label", "LABEL", "l", "label"}
  {"Override block size", "SIZE", "b", "bs", "blocksize"},
  {"Override file count", "COUNT", "f", "files"},
  {"Format mounted filesystem (DANGEROUS)", false, "F", "force"},
  {"I know what I'm doing, don't prompt me", false, "i-know-what-im-doing"},
  {"Show this help message", false, "h", "help"},
  exit_on_bad_opt = true,
  help_message = "pass '--help' for usage information\n",
  argv = ...
}

local function showusage()
  io.stderr:write(([[
usage: mkfs.sfs [options] VOLUME
Format the given block device as a SimpleFS volume.

options:
%s

Copyright (c) 2023 ULOS Developers under the GNU GPLv3.
]]):format(usage))
  os.exit(1)
end

if #args == 0 or opts.h then
  showusage()
end

local device = args[1]

if opts.b then
  opts.b = tonumber(opts.b)
  if type(opts.b) ~= "number" then
    io.stderr:write("mkfs.sfs: argument to -b must be a number\n")
    os.exit(1)
  end

  local log = math.log(opts.b, 2)
  if opts.b < 512 or math.floor(log) ~= log then
    io.stderr:write("mkfs.sfs: block size must be a power of 2 and at least 512")
    os.exit(1)
  end
end

if opts.f then
  opts.f = tonumber(opts.f)
  if type(opts.f) ~= "number" then
    io.stderr:write("mkfs.sfs: argument to -f must be a number\n")
    os.exit(1)
  end
end

local hd, err = io.open(device, "rwb")
if not hd then
  io.stderr:write("mkfs.sfs: ", err, "\n")
  os.exit(2)
end

local structures = {
  superblock = {
    pack = "<c4BBI2I2I3I3c19",
    names = {"signature", "flags", "revision", "nl_blocks", "blocksize", "blocks", "blocks_used", "label"}
  },
  nl_entry = {
    pack = "<I2I2I2I2I2I4I8I8I2I2c30",
    names = {"flags", "datablock", "next_entry", "last_entry", "parent", "size", "created", "modified", "uid", "gid", "fname"}
  },
}

local constants = {
  superblock = 0,
  blockmap = 1,
  namelist = 2,
  F_FIFO = 0x1000,
  F_CHAR = 0x2000,
  F_DIR = 0x4000,
  F_BLOCK = 0x6000,
  F_REGULAR = 0x8000,
  F_LINK = 0xA000,
  F_SOCKET = 0xC000,
  F_TYPE = 0xF000,
}

local function pack(name, data)
  local struct = structures[name]
  local fields = {}
  for i=1, #struct.names do
    fields[i] = data[struct.names[i]]
    if fields[i] == nil then
      error("pack:structure " .. name .. " missing field " .. struct.names[i])
    end
  end
  return string.pack(struct.pack, table.unpack(fields))
end

-- return current in-game time
local function time()
  -- number of ticks since world creation, times 50 for approximate ms
  return math.floor((os.time() * 1000/60/60 - 6000) * 50)
end

-- determine optimal-ish sizes for various filesystem bits
local function getOptimalSizes(fssize)
  -- maximum PRACTICAL number of blocks is 65536
  -- maximum ACTUAL number of blocks is 16777216 so use that instead
  blocksize = opts.b or math.ceil(fssize/0xFFFFFF)*1024
  -- we want no more files than blocks, so set namelist size based on that
  local nl_size = opts.f or (fssize/blocksize)*64
  -- determine blockmap size from block count
  local bmap_size = fssize/blocksize/8
  return blocksize, nl_size, bmap_size
end

local null = "\0"

local function readBlock(n)
  hd:seek("set", n*1024)
  return hd:read(1024)
end

local function writeBlock(n, d)
  hd:seek("set", n*1024)
  hd:write(d)
end

local bmap = {}
local function writeBlockMap()
  local data = ""
  for i=0, #bmap, 8 do
    local c = 0
    for j=0, 7 do
      c = c | (2^j)*bmap[i+j]
    end
    data = data .. string.char(c)
  end
  writeBlock(constants.blockmap, data)
end

local function writeNamelistEntry(n, ent)
  local data = pack("nl_entry", ent)
  local offset = n * 64 % 512
  local block = math.floor(n/8)
  -- superblock is first block, blockmap is second, namelist comes after those
  local blockData = readBlock(block+constants.namelist)
  blockData = blockData:sub(0, offset)..data..blockData:sub(offset + 65)
  writeBlock(block+constants.namelist, blockData)
end

local function format()
  local size = hd:seek("end")
  if opts.e then
    print("zeroing drive")
    local N = null:rep(4096)
    hd:seek("set")
    for i=1, size/4096 do
      hd:write(N)
    end
  end
  hd:seek("set")
  local sblk, snl, sbmap = getOptimalSizes(size)
  print("formatting as SimpleFS")
  print("block size: " .. sblk)
  print("file count: " .. math.floor(snl/64))
  print("block count: " .. math.floor(sbmap*8))
  print("writing superblock...")
  local reserve = math.ceil(snl/sblk + 1 + sbmap/sblk)
  print("reserving " .. reserve .. " blocks (overhead " ..
    math.floor(reserve*sblk/1024) .."kb)")
  local superblock = pack("superblock", {
    signature = "\x1bSFS",
    flags = 0,
    revision = 0,
    nl_blocks = snl/sblk,
    blocksize = sblk,
    blocks = math.min(sbmap*8, (size/sblk)),
    blocks_used = reserve,
    label = opts.l or
      "simplefs-"..math.floor(math.random(1000000000, 9999999999))
  })
  writeBlock(constants.superblock, superblock)

  print("writing blockmap...")
  -- write a whole block's worth
  bmap = {}
  for i=0, (sbmap*8)-1 do
    bmap[i] = 0
  end
  -- reserve first few blocks for superblock, namelist, and blockmap
  for i=0, reserve do
    bmap[i] = 1
  end
  writeBlockMap()

  print("writing namelist... ")

  hd:seek("set",constants.namelist*1024)
  for i=1, (snl/sblk * (sblk/512)) - 1 do
    hd:write(null:rep(512))
  end

  local nl_entry_root = {
    flags = constants.F_DIR | -- directory
      -- default root permissions rwx-r-xr-x
      0x100 | 0x80 | 0x40 |
      0x20 | 0x10 |
      0x4 | 0x1,
    datablock = 0,
    next_entry = 0,
    last_entry = 0,
    parent = 0,
    size = 0,
    -- no userspace real-time facilities yet, so use os.clock ig
    created = time(),
    modified = time(),
    uid = 0,
    gid = 0,
    fname = ""
  }
  writeNamelistEntry(0, nl_entry_root)
  print("formatting done!")
end

if readBlock(0):sub(5,5):byte() & 1 ~= 0 then
  io.stderr:write("\27[91m", device, ": filesystem is dirty, and may be mounted\27[39m\n")
  if opts.F then
    if not opts["i-know-what-im-doing"] then
      io.write("REALLY format ", device, "? [y/N] ")
      if (io.read() or ""):lower() ~= "y" then os.exit(3) end
    end
  else
    io.stderr:write("not formatting ", device, "\n")
    os.exit(3)
  end
end

format()

hd:close()
