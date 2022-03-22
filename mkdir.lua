--!lua
local args = ({...})[1]

if not args[2] then
    coroutine.yield("syscall", "write", 1, "Usage: mkdir <path>\n")
    coroutine.yield("syscall", "exit", 0)
end

local s, e = coroutine.yield("syscall", "mkdir", args[2])
if not s then
    coroutine.yield("syscall", "write", 1, args[1] .. ": " .. (
        (e == 17 and "File exists") or
        (e == 2 and "Parent directory not found") or
        (e == 13 and "Permission denied") or
        tostring(e)
    ) .. "\n")
    coroutine.yield("syscall", "exit", 1)
end
