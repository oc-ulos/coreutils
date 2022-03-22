--!lua
local args = ({...})[1]

if not args[2] then
    coroutine.yield("syscall", "write", 1, "Usage: " .. args[1] .. " <path>\n")
    coroutine.yield("syscall", "exit", 0)
end

local s, e = coroutine.yield("syscall", "unlink", args[2])
if not s then
    coroutine.yield("syscall", "write", 1, "Error: " .. (
        (e == 2 and "no such file or directory") or
        (e == 13 and "permission denied") or
        tostring(e)
    ) .. "\n")
    coroutine.yield("syscall", "exit", 1)
end
