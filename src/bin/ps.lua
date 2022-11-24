--!lua
-- ps implementation

local argv = ...

local dirent = require("posix.dirent")

local files = dirent.dir("/proc")

for i=#files, 1, -1 do
  if not tonumber(files[i]) then
    table.remove(files, i)
  end
end

table.sort(files, function(a,b) return tonumber(a) < tonumber(b) end)

local function read(f)
  local h = io.open(f, "r")
  return h:read("a"), h:close()
end

print("  PID  PPID   UID CMD")

for i=1, #files, 1 do
  local path = "/proc/"..files[i]
  local cmdline = {}

  if argv[1] == "a" then
    local cmdlinefiles = dirent.dir(path.."/cmdline/")
    table.sort(cmdlinefiles, function(a,b) return tonumber(a) < tonumber(b) end)

    for _, file in ipairs(cmdlinefiles) do
      cmdline[#cmdline + 1] = read(path.."/cmdline/"..file)
    end
    cmdline = table.concat(cmdline, " ")

  else
    cmdline = read(path.."/cmdline/0")
  end

  print(string.format("%5s %5s %5s %s",
    read(path.."/pid"),
    read(path.."/ppid"),
    read(path.."/uid"),
    cmdline))
end
