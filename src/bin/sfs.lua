--!lua
-- test simplefs driver
-- prototyped in userspace, should be able to port it to the kernel
-- pretty easily

local hd = assert(io.open("/dev/hda", "rwb"))

local structures = {
  superblock = {
    pack = "<BI2I2I3I3",
    names = {"flags", "nl_blocks", "blocksize", "blocks", "blocks_used"}
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

local function unpack(name, data)
  local struct = structures[name]
  local ret = {}
  local fields = table.pack(string.unpack(struct.pack, data))
  for i=1, #struct.names do
    ret[struct.names[i]] = fields[i]
    if fields[i] == nil then
      error("unpack:structure " .. name .. " missing field " .. struct.names[i])
    end
  end
  return ret
end

-- return current in-game time
local function time()
  -- number of ticks since world creation, times 50 for approximate ms
  return math.floor((os.time() * 1000/60/60 - 6000) * 50)
end

-- keys in kb, table values in bytes
local sizes = {
  [512] = {blk = 1024, nl = 65536, bmap = 64},
  [1024] = {blk = 1024, nl = 131072, bmap = 128},
  [2048] = {blk = 1024, nl = 131072, bmap = 256},
  [4096] = {blk = 1024, nl = 196608, bmap = 512},
}
local null = "\0"

local function format()
  print("formatting with block size 1024")
  print("writing superblock...")
  local size = hd:seek("end")
  hd:seek("set")
  local defaults = sizes[size/1024]
  if not defaults then
    error("no default for fs size " .. size)
  end
  local superblock = pack("superblock", {
    flags = 0,
    nl_blocks = defaults.nl/defaults.blk,
    blocksize = defaults.blk,
    blocks = math.min(defaults.bmap*8, (size/defaults.blk)),
    blocks_used = 0,
  })
  hd:write(superblock .. null:rep(defaults.blk - #superblock))

  print("writing blockmap...")
  -- write a whole block's worth
  local map = null:rep(math.ceil(defaults.bmap/defaults.blk)*defaults.blk)
  -- reserve first few blocks for superblock, namelist, and blockmap
  local reserve = defaults.nl/defaults.blk + 1 * #map/defaults.blk
  for i=1, reserve do
    map = map:sub(0,i-1)..string.char(map:sub(i,i):byte()|2^(i%8))..map:sub(i+1)
  end
  hd:write(map)

  io.write("writing namelist.../")
  local nl_entry_root = pack("nl_entry", {
    flags = 0x4000 | -- directory
      -- default root permissions rwx-r-xr-x
      0x100 | 0x80 | 0x40 |
      0x20 | 0x10 |
      0x4 | 0x1,
    datablock = 1,
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
  })
  local nl_entry_blank = null:rep(64)
  hd:write(nl_entry_root)
  local spin = setmetatable({v=0,"-","\\","|","/"}, {__call=function(s)
    s.v = (s.v%4) + 1
    return s[s.v]
  end})
  for i=1, (defaults.nl/defaults.blk * (defaults.blk/64)) - 1 do
    hd:write(nl_entry_blank)
    if i % 64 == 0 then
      io.stdout:write("\27[D"..spin())
      io.stdout:flush()
    end
  end
  print("\27[D \nformatting done!")
end

local function split(path)
  local segs = {}
  for s in path:gmatch("[^/\\]+") do
    if s == ".." then segs[#segs] = nil
    else segs[#segs+1] = s end
  end
  return segs
end

local function readBlock(n)
  hd:seek("set", n*1024)
  return hd:read(1024)
end

local function writeBlock(n, d)
  hd:seek("set", n*1024)
  hd:write(d)
end

local bmap = {}
local sblock = {}

local function readSuperblock()
  local data = readBlock(constants.superblock)
  sblock = unpack("superblock", data)
end

local function writeSuperblock()
  writeBlock(constants.superblock, pack("superblock", sblock))
end

local function readBlockMap()
  local data = readBlock(constants.blockmap)
  bmap = {}
  for c in data:gmatch(".") do
    c = c:byte()
    for i=0, 7 do
      bmap[#bmap+1] = (c & 2^i ~= 0) and 1 or 0
    end
  end
end

local function writeBlockMap()
  local data = ""
  for i=1, #bmap, 8 do
    local c = 0
    for j=0, 7 do
      c = c | (2^j)*bmap[i+j]
    end
    data = data .. string.char(c)
  end
  writeBlock(constants.blockmap, data)
end

local function allocateBlocks(count)
  local index = 0
  local blocks = {}
  for i=1, count do
    repeat
      index = index + 1
    until bmap[index] == 0 or not bmap[index]
    blocks[#blocks+1] = index
    bmap[index] = 1
  end
  if index > #bmap then error("out of space") end
  return blocks
end

local function freeBlocks(blocks)
  for i=1, #blocks do
    bmap[blocks[i]] = 0
  end
end

local function readNamelistEntry(n)
  local offset = n * 64 % 512
  local block = math.floor(n/8)
  -- superblock is first block, blockmap is second, namelist comes after those
  local blockData = readBlock(block+constants.namelist)
  local namelistEntry = blockData:sub(offset, offset + 63)
  return unpack("nl_entry", namelistEntry)
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

local knownNamelist = {}
local maxKnown = 0
local function allocateNamelistEntry()
  local lastBlock = block
  local blockData
  for i=1, #knownNamelist do
    if not knownNamelist[i] then
      knownNamelist[i] = true
      return i
    end
  end
  for n=1, sblock.nl_blocks*8 do
    local offset = n * 64 % 512
    local block = math.floor(n/8)
    blockData = blockData or readBlock(offset+constants.namelist)
    local namelistEntry = blockData:sub(offset, offset + 63)
    local v = unpack("nl_entry", namelistEntry)
    knownNamelist[n] = true
    maxKnown = math.max(maxKnown, n)
    if v.flags == 0 then
      return n
    end
  end
  error("no free namelist entries")
end

local function freeNamelistEntry(n, evenifdir)
  local entry = readNamelistEntry(n)
  if entry.flags & constants.F_TYPE == constants.F_DIR then
    if entry.datablock ~= 0 then
      return nil, "cannot unlink a directory with things in it"
    elseif not evenifdir then
      return nil, "cannot unlink a directory without evenifdir"
    end
  end
  knownNamelist[n] = false
  entry.flags = 0
  entry.datablock = 0
  -- remove from the doubly linked list that is the directory listing
  if entry.next_entry ~= 0 then
    local nextEntry = readNamelistEntry(entry.next_entry)
    nextEntry.last_entry = entry.last_entry
    writeNamelistEntry(entry.next_entry, nextEntry)
  end
  if entry.last_entry ~= 0 then
    local nextEntry = readNamelistEntry(entry.last_entry)
    nextEntry.next_entry = entry.next_entry
    writeNamelistEntry(entry.last_entry, nextEntry)
  end
  -- make sure the parent entry doesn't wind up pointing to an invalid one
  local parent = readNamelistEntry(entry.parent)
  if parent.datablock == n then
    parent.datablock = entry.next_entry
    writeNamelistEntry(entry.parent, parent)
  end
  writeNamelistEntry(n, entry)
end

local function getNext(ent)
  if ent.next_entry == 0 then
    return nil
  end
  return readNamelistEntry(ent.next_entry), ent.next_entry
end

local function getLast(ent)
  if ent.last_entry == 0 then
    return nil
  end
  return readNamelistEntry(ent.last_entry), ent.last_entry
end

local function resolveParent(path)
  local segments = split(path)
  local dir = readNamelistEntry(0)
  local current, cid = getNext(dir)
  for i=1, #segments - 1 do
    while current and current.fname ~= segments[segment] do
      current, cid = getNext(current)
    end
    if not current then
      error("path not found")
    end
  end
  return current, cid
end

local function mkfileentry(name, flags)
  print("creating entry for '" .. name .."'")
  local segments = split(name)
  local parent, pid = resolveParent(name)
  local n = allocateNamelistEntry()
  if parent.flags & constants.F_TYPE ~= constants.F_DIR then
    error("parent is not a directory, panicing")
  end
  local last_entry = 0
  if parent.datablock == 0 then
    parent.datablock = n
  else
    local first = readNamelistEntry(parent.datablock)
    local last, index
    repeat
      local next_entry, next_index = getNext(last or first)
      if next_entry then last, index = next_entry, next_index end
    until not next_entry
    last.next_entry = n
    last_entry = index
    writeNamelistEntry(index, last)
  end

  writeNamelistEntry(n, {
    flags = flags,
    datablock = 0,
    next_entry = 0,
    last_entry = last_entry,
    parent = pid,
    size = 0,
    created = time(),
    modified = time(),
    uid = 0,
    gid = 0,
    fname = segments[#segments]
  })
end

format()
readSuperblock()
readBlockMap()

hd:close()
