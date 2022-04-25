--!lua
io.write(math.floor(require("posix.unistd").getuid()).."\n")
