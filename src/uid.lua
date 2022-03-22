--!lua

local sys = require("syscalls")

io.write(sys.getuid().."\n")

sys.exit(0)
