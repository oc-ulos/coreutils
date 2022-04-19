--!lua

local dirent = require("posix.dirent")
local errno = require("posix.errno")
local stat = require("posix.sys.stat")

local argv = ...

argv[1] = argv[1] or "."

for i=1, #argv, 1 do
  if #argv > 1 then print(argv[i]..":") end
  local statx, eno = stat.lstat(argv[i])
  if not statx then
    io.stderr:write(argv[0], ": ", errno.errno(eno), "\n")
    os.exit(1)
  elseif stat.S_ISDIR(statx.st_mode) == 0 then
    io.stderr:write(argv[0], ": ", errno.errno(errno.ENOTDIR), "\n")
    os.exit(1)
  else
    for file in dirent.files(argv[i]) do
      local sx = stat.lstat(argv[i].."/"..file)
      io.write(file, "\t")
    end
  end
  io.write("\n")
end

