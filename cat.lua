--!lua
local args = ({...})[1]

--- Perform a system call
---@param call string
---@vararg any
local function syscall(call, ...)
    return coroutine.yield("syscall", call, ...)
end

if not args[2] then
    syscall("write", 1, "Usage: " .. args[1] .. " <path>\n")
    syscall("exit", 0)
end

for i=2, #args do
    local path = args[i]
    local fd, errno = syscall("open", path, "r")
    if fd then
        local data = syscall("read", fd, "a")
        syscall("write", 1, data)
        syscall("close", fd)
    else
        syscall("write", 1, args[1] .. ": " .. path .. ": " .. (
            (errno == 2 and "No such file or directory") or
            (errno == 13 and "Permission denied") or
            "Unknown error"
        ) .. "\n")
    end
end

syscall("exit", 0)
