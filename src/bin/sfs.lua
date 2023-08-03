--!lua
-- test simplefs driver
-- prototyped in userspace, should be able to port it to the kernel
-- pretty easily

local args = ...

local hd = assert(io.open("/dev/hda", "rwb"))

local structures = {
  superblock = {
    pack = "<BBI2I2I3I3",
    names = {"flags", "revision", "nl_blocks", "blocksize", "blocks", "blocks_used"}
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
  local x = 0
  for c in data:gmatch(".") do
    c = c:byte()
    for i=0, 7 do
      bmap[x] = (c & 2^i ~= 0) and 1 or 0
      x = x + 1
    end
  end
end

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

local function allocateBlocks(count)
  local index = 0
  local blocks = {}
  for i=1, count do
    repeat
      index = index + 1
    until bmap[index] == 0 or not bmap[index]
    blocks[#blocks+1] = index
    bmap[index] = 1
    print("allocate block " .. index)
    writeBlock(index, null:rep(sblock.blocksize))
  end
  if index > #bmap then error("out of space") end
  sblock.blocks_used = sblock.blocks_used + #blocks
  return blocks
end

local function freeBlocks(blocks)
  for i=1, #blocks do
    sblock.blocks_used = sblock.blocks_used - bmap[blocks[i]]
    bmap[blocks[i]] = 0
  end
end

local function readNamelistEntry(n)
  local offset = n * 64 % 512 + 1
  local block = math.floor(n/8)
  -- superblock is first block, blockmap is second, namelist comes after those
  local blockData = readBlock(block+constants.namelist)
  local namelistEntry = blockData:sub(offset, offset + 63)
  local ent = unpack("nl_entry", namelistEntry)
  ent.fname = ent.fname:gsub("\0", "")
  return ent
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
  for i=1, maxKnown do
    if not knownNamelist[i] then
      knownNamelist[i] = true
      return i
    end
  end
  local blockData
  local lastBlock = 0
  for n=0, sblock.nl_blocks*8 do
    local offset = n * 64 % 512 + 1
    local block = math.floor(n/8)
    if block ~= lastBlock then blockData = nil end
    blockData = blockData or readBlock(block+constants.namelist)
    local namelistEntry = blockData:sub(offset, offset + 63)
    local v = unpack("nl_entry", namelistEntry)
    knownNamelist[n] = true
    maxKnown = math.max(maxKnown, n)
    --print("V", n, v.flags, v.fname)
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

local function resolve(path, offset)
  offset = offset or 0
  local segments = split(path)
  local dir = readNamelistEntry(0)
  local current, cid = dir, 0
  if #segments == offset then return current, cid end
  for i=1, #segments - offset do
    --print("search '"..current.fname.."' ("..cid..")")
    current, cid = readNamelistEntry(current.datablock), current.datablock
    while current and current.fname ~= segments[i] do
      --print("want '"..segments[i].."'", "have '"..current.fname.."' ("..cid..")")
      current, cid = getNext(current)
    end
    if not current then
      return nil, "path not found"
    end
    --print("want '"..segments[i].."'", "have '"..current.fname.."' ("..cid..")")
  end
  return current, cid
end

local function mkfileentry(name, flags)
  print("creating entry for '" .. name .."'")
  local segments = split(name)
  local insurance = resolve(name)
  if insurance then
    print("file already exists!!!")
    return
  end
  local parent, pid = resolve(name, 1)
  if not parent then --[[print(pid)]] return nil end
  --print("parent is " .. pid, parent.flags & constants.F_TYPE, constants.F_DIR)
  if parent.flags & constants.F_TYPE ~= constants.F_DIR then
    error("parent is not a directory, panicing")
  end
  local last_entry = 0
  --print("parent datablock " .. parent.datablock)
  local n = allocateNamelistEntry()
  if parent.datablock == 0 then
    parent.datablock = n
    writeNamelistEntry(pid, parent)
  else
    local first = readNamelistEntry(parent.datablock)
    local last, index = first, parent.datablock
    repeat
      local next_entry, next_index = getNext(last)
      if next_entry then last, index = next_entry, next_index end
    until not next_entry
    --print(last.fname, index)
    last.next_entry = n
    last_entry = index
    writeNamelistEntry(index, last)
  end

  --print("writing", segments[#segments], "to", n, flags)
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

local function rmfileentry(name)
  print("removing file entry '"..name.."'")
  local segments = split(name)
  local entry, eid = resolve(name)
  if not entry then
    print("file was not found!!")
  else
    freeNamelistEntry(eid)
  end
end

local function getlisting(dir)
  print("get directory listing of '"..dir.."'")
  local entry, eid = resolve(dir)
  if entry.flags & constants.F_TYPE ~= constants.F_DIR then
    print("not a directory!!!")
  else
    local current, cid = readNamelistEntry(entry.datablock), entry.datablock
    if cid == 0 then return end
    repeat
      print(current.fname)
      current, cid = getNext(current)
    until not current
  end
end

local function getBlock(ent, pos, create, all)
  local count = math.ceil((pos+1) / (sblock.blocksize-3))
  local current = ent.datablock
  local all = {}
  for i=1, count-1 do
    local data = readBlock(current)
    local nxt = ("<I3"):unpack(data:sub(-3))
    if nxt == 0 then
      if create then
        nxt = allocateBlocks(1)[1]
        data = data:sub(1,-4)..("<I3"):pack(nxt)
        writeBlock(current, data)
      else
        if all then return current, all end
        return current
      end
    end
    all[#all+1] = current
    current = nxt
  end
  if all then return current, all end
  return current
end

local function open(file, mode)
  print("open '"..file.."'")
  local entry, eid = resolve(file)
  if not entry then
    print("file does not exist!!!")
    return
  end

  local pos = 0
  if mode == "w" then
    local final, blocks = getBlock(entry, 0xFFFFFF, false, true)
    blocks[#blocks+1] = final
    freeBlocks(blocks)
    entry.datablock = allocateBlocks(1)[1]
    entry.size = 0
  elseif mode == "a" then
    pos = entry.size
  end

  return {
    entry = entry, eid = eid, pos = 0, mode = mode
  }
end

local function seek(fd, pos)
  if fd.mode == "w" then
    fd.entry.size = math.max(0, math.min(fd.entry.size, pos))
    getBlock(fd.entry, pos, true)
  end
  fd.pos = math.max(0, math.min(fd.entry.size, pos))
end

local function write(fd, data)
  local offset = fd.pos % (sblock.blocksize-3)

  repeat
    local blockID = getBlock(fd.entry, fd.pos, true)
    local block = readBlock(blockID)
    local write = data:sub(1, (sblock.blocksize-3) - offset)
    data = data:sub(#write+1)
    fd.pos = fd.pos + #write
    fd.entry.size = math.max(fd.entry.size, fd.pos)

    if #write == sblock.blocksize-3 then
      block = write .. block:sub(-3)
    else
      block = block:sub(0, offset) .. write ..
        block:sub(offset + #write + 1)
    end

    writeBlock(blockID, block)
  until #data == 0

  return true
end

local function read(fd, len)
  if fd.pos < fd.entry.size then
    len = math.min(len, fd.entry.size - fd.pos)
    local offset = fd.pos % (sblock.blocksize-3) + 1
    local data = ""

    repeat
      local blockID = getBlock(fd.entry, fd.pos)
      local block = readBlock(blockID)
      local read = block:sub(1,-4):sub(offset, offset+len-1)
      print(offset,#read,fd.pos)
      data = data .. read
      fd.pos = fd.pos + #read
      offset = fd.pos % (sblock.blocksize-3) + 1
      len = len - #read
    until len <= 0

    return data
  end
end

local function close(fd)
  if fd.mode == "w" then fd.entry.modified = time() end
  writeNamelistEntry(fd.eid, fd.entry)
end

local function format(fast)
  print("formatting " .. (fast and "(fast) " or "") .. "with block size 1024")
  print("writing superblock...")
  local size = hd:seek("end")
  hd:seek("set")
  local defaults = sizes[size/1024]
  if not defaults then
    error("no default for fs size " .. size)
  end
  local reserve = math.ceil(defaults.nl/defaults.blk + 1 + defaults.bmap/defaults.blk)
  print("reserving " .. reserve .. " blocks")
  local superblock = pack("superblock", {
    flags = 0,
    revision = 0,
    nl_blocks = defaults.nl/defaults.blk,
    blocksize = defaults.blk,
    blocks = math.min(defaults.bmap*8, (size/defaults.blk)),
    blocks_used = reserve
  })
  writeBlock(constants.superblock, superblock)

  print("writing blockmap...")
  -- write a whole block's worth
  bmap = {}
  for i=0, (defaults.bmap*8)-1 do
    bmap[i] = 0
  end
  -- reserve first few blocks for superblock, namelist, and blockmap
  for i=0, reserve do
    bmap[i] = 1
  end
  writeBlockMap()

  io.write("writing namelist... ")

  if not fast then
    hd:seek("set",constants.namelist*1024)
    for i=1, (defaults.nl/defaults.blk * (defaults.blk/64)) - 1 do
      hd:write(null:rep(64))
      if i % 64 == 0 then
        io.stdout:write("\27[21G"..i.."/"..math.floor(defaults.nl/defaults.blk*(defaults.blk/64))-1):flush()
      end
    end
  else
    print("\27[D \nfast mode - not zeroing namelist")
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
  print("\27[D \nformatting done!")
end

if args[1] == "-nf" then
  print("skipping format")
else
  format(args[1] == "-ff")
end
print("reading superblock")
readSuperblock()
print("reading blockmap")
readBlockMap()
mkfileentry("test", constants.F_REGULAR | 448 | 56 | 7)
mkfileentry("dir", constants.F_DIR | 448 | 56 | 7)
mkfileentry("dir/test", constants.F_REGULAR | 448 | 56 | 7)
mkfileentry("does/not/exist", constants.F_REGULAR | 448 | 56 | 7)

print("creating file 'test'")
local handle = open("test", "w")
write(handle, "this is some test data.\n")
close(handle)

--print(getlisting("/"))
--print(getlisting("/dir"))

print("read back file 'test'")
handle = open("test", "r")
print("expect 'this is some test data.\n', got '".. read(handle, 24).."'")
seek(handle, 15)
print("expect 'st data.\n', got '".. read(handle, 9).."'")
close(handle)

print("--TEST MULTI-BLOCK FILES--")
local data = string.rep("#@$%",1024)
handle = open("dir/test", "w")
write(handle, data)
close(handle)

print("read back file, verify data")
handle = open("dir/test","r")
local written = read(handle, #data)
close(handle)
if written ~= data then
  print("\27[91mmismatch!!!!!!\27[39m")
  print(string.format("original length: %d, readback length: %d", #data, #written))
  for i=1, #written do
    if written:sub(i,i)~=data:sub(i,i) then
      print(string.format("mismatched character at %d",i))
      print(string.format("original '%s', readback '%s'", data:sub(i,i),written:sub(i,i)))
    end
  end
else
  print("\27[92mmatch!!!\27[39m")
end

if false then
  print(getlisting("/"))
  print(getlisting("/dir"))
  rmfileentry("/dir/test")
  print(getlisting("/dir"))
  rmfileentry("/test")
  print(getlisting("/"))
end

print("save superblock/blockmap")
writeSuperblock()
writeBlockMap()

hd:close()
