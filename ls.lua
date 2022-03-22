--!lua
local dirfd = coroutine.yield("syscall", "opendir", ({...})[1][2] or ".")

for dirent in function() return coroutine.yield("syscall", "readdir", dirfd) end do
  coroutine.yield("syscall", "write", 1, dirent.name .. "\n")
end

coroutine.yield("syscall", "close", dirfd)
