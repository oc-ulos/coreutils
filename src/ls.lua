--!lua
local dirent = require("posix.dirent")

local args = ...

args[1] = args[1] or "."

for i=1, #args, 1 do
  for file in dirent.files(args[i] or ".") do
    io.write(file, "\t")
  end
end

io.write("\n")
