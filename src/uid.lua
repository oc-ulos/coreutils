--!lua

--- Perform a system call
---@param call string
---@vararg any
local function syscall(call, ...)
  return coroutine.yield("syscall", call, ...)
end

syscall("write", 1, "Your UID is " .. tonumber(syscall("getuid")) .. "\n")
