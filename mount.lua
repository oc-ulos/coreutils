--!lua
local args = ({...})[1]
local device = args[2]
local mountpoint = args[3] or "."

if not device then
    coroutine.yield("syscall", "write", 1, "Usage: mount <device> [mountpoint]\n")
    coroutine.yield("syscall", "exit", 0)
end

local s, e = coroutine.yield("syscall", "mount", device, mountpoint)
if not s then
    coroutine.yield("syscall", "write", 1, args[1] .. ": " .. (
        (e == 13 and "Permission denied") or
        (e == 2 and "Mount point not found") or
        (e == 20 and "Mount point is not a directory") or
        (e == 16 and "Mount point is already in use") or
        (e == 49 and "Device not found") or
        (e == 19 and "Device is not supported") or
        tostring(e)
    ) .. "\n")
    coroutine.yield("syscall", "exit", 1)
end
