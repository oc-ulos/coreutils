--!lua
local args = ({...})[1]

--- Perform a system call
---@param call string
---@vararg any
local function syscall(call, ...)
  return coroutine.yield("syscall", call, ...)
end

---@param fmt string
---@vararg any
local function printf(fmt, ...)
  syscall("write", 1, string.format(fmt, ...))
end

local function elookup(code)
  return (
    (code == 1 and "Permission denied") or
    ("Unknown error " .. tonumber(code))
  )
end

local function halt()
  local s, e = syscall("reboot", "halt")
  if not s then
    printf("%s\n", elookup(e))
  end
end

local function poweroff()
  local s, e = syscall("reboot", "poweroff")
  if not s then
    printf("%s\n", elookup(e))
  end
end

local function reboot()
  local s, e = syscall("reboot", "restart")
  if not s then
    printf("%s\n", elookup(e))
  end
end

if args[2] then
  if args[2] == "--halt" then
    halt()
  elseif args[2] == "--poweroff" or args[2] == "-p" then
    poweroff()
  elseif args[2] == "--reboot" then
    reboot()
  else
    coroutine.yield("syscall", "write", 1, "Bad argument.\n")
  end
else
  if args[1] == "halt" then
    halt()
  elseif args[1] == "poweroff" then
    poweroff()
  elseif args[1] == "reboot" then
    reboot()
  else
    coroutine.yield("syscall", "write", 1, "Invalid executable name and no arguments.\n")
  end
end
