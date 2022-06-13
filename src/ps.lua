--!lua
-- ps implementation
-- takes no arguments at this time

local dirent = require("posix.dirent")

local files = dirent.dir("/proc")

for i=#files, 1, -1 do
  if not tonumber(files[i]) then
    table.remove(files, i)
  end
end

table.sort(files)

local function read(f)
  local h = io.open(f, "r")
  return h:read("a"), h:close()
end

print("  PID  PPID   UID CMD")
for i=1, #files, 1 do
  local path = "/proc/"..files[i]
  print(string.format("%5s %5s %5s %s",
    read(path.."/pid"),
    read(path.."/ppid"),
    read(path.."/uid"),
    read(path.."/cmdline/0")))
end
