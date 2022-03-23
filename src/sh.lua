--!lua
-- A shell with grammars based on Bash.
local args = ({...})[1]

--- Perform a syscall.
---@param call string
local function syscall(call, ...)
  return coroutine.yield("syscall", call, ...)
end

--- Print a formatted string to stdout(1).
---@param fmt string
local function printf(fmt, ...)
  return syscall("write", 1, string.format(fmt, ...))
end

--- Read a line from stdin(0).
---@return string
local function readline()
  return syscall("read", 0, "l")
end

--- Tokenize a string.
---
--- Devnote: doing this char-by-char is still better than pulling out my hair.
---@param str string
---@return table
local function tokenize(str)
  local tokens = {}
  
  do
    local chars = {}

    for char in str:gmatch(".") do
      table.insert(chars, char)
    end

    -- Metachars: | & ; ( ) < > space tab newline
    local metachars = {
      ["|"] = true,
      ["&"] = true,
      [";"] = true,
      ["("] = true,
      [")"] = true,
      ["<"] = true,
      [">"] = true,
      [" "] = true,
      ["\t"] = true,
      ["\n"] = true,
    }

    -- Control operators: || & && ; ;; ;& ;;& ( ) | |& newline
    local ctrl = {
      ["||"] = true,
      ["&"] = true,
      ["&&"] = true,
      [";"] = true,
      [";;"] = true,
      [";&"] = true,
      [";;&"] = true,
      ["("] = true,
      [")"] = true,
      ["|"] = true,
      ["|&"] = true,
      ["\n"] = true,
    }

    local quotes = {
      ["'"] = true,
      ['"'] = true,
    }

    do
      local buffer = ""
      local quotechar = nil
      local skip = 0

      local function flush()
        if buffer ~= "" then
          table.insert(tokens, buffer)
          buffer = ""
        end
      end

      for i = 1, #chars do
        if skip > 0 then skip = skip - 1 goto continue end
        local char = chars[i]

        if quotechar then
          if char == quotechar then
            quotechar = nil
            flush()
          else
            buffer = buffer .. char
          end
        elseif quotes[char] then
          quotechar = char
        else
          if metachars[char] then
            flush()
            local next = chars[i + 1] or ""

            if ctrl[char .. next] then
              skip = 1
              table.insert(tokens, char .. next)
            else
              table.insert(tokens, char) -- Some metachars are used.
            end
          else
            buffer = buffer .. char
          end
        end

        ::continue::
      end
    end
  end

  return tokens
end

local builtins = {
  cd = function(path)
    local s, e = syscall("chdir", path)
    if not s then
      printf("%s: %s\n", path, (
        (e == 2) and "No such file or directory" or
        (e == 13) and "Permission denied" or
        tonumber(e)
      ))
    end
  end
}

--- Parse the input.
---@param input string
local function parse(input)
  if input == "exit\n" then syscall("exit", 0) end
  local tokens = tokenize(input)
  local env = {}
  local command = {}

  do
    local is_cmd = false

    local exclude_tokens = {
      ["|"] = true,
      ["&"] = true,
      [";"] = true,
      ["("] = true,
      [")"] = true,
      ["<"] = true,
      [">"] = true,
      [" "] = true,
      ["\t"] = true,
      ["\n"] = true,
    }

    for i, token in ipairs(tokens) do
      if not exclude_tokens[token] then
        if is_cmd then
          table.insert(command, token)
        else
          local key, value = token:match("^([%w_]+)=(.*)$")
          
          if key then
            table.insert(env, key .. "=" .. value)
          else
            table.insert(command, token)
            is_cmd = true
          end
        end
      end
    end
  end

  if #command == 0 then return
  elseif builtins[command[1]] then
    builtins[command[1]](table.unpack(command, 2))
    return
  end

  local paths = {
    "/bin/?",
    "/bin/?.lua",
    "./?",
    "./?.lua",
  }
  local foundpath = nil

  if command[1]:sub(1,1) == "/" then
    local stat, errno = syscall("stat", command[1])
    if not stat then
      printf("%s: No such file or directory\n", command[1])
      return
    elseif bit32.band(stat.mode, 0x8000) == 0 then
      printf("%s: Is a directory\n", command[1])
      return
    end
    foundpath = command[1]
  else
    for _, path in ipairs(paths) do
      path = path:gsub("%?", command[1])
  
      local stat, errno = syscall("stat", path)
      if stat and bit32.band(stat.mode, 0x8000) == 0x8000 then
        foundpath = path
        break
      end
    end
  end

  if not foundpath then
    printf("sh: %s: command not found\n", command[1])
    return
  end

  if foundpath then
    command[0] = table.remove(command, 1)
    local pid = syscall("fork", function()
      local _, errno = syscall("execve", foundpath, command, env)
      if errno then
        printf("execve: %s\n", (
          (errno == 2) and "No such file or directory" or
          (errno == 13) and "Permission denied" or
          tonumber(errno)
        ))
      end
    end)
    if tokens[#tokens - 1] ~= "&" then
      syscall("wait", pid)
    end
  else
    printf("%s: command not found\n", command[1])
  end
end

if args[2] == "-c" then
  parse(args[3] .. "\n")
  syscall("exit", 0)
end

while true do
  printf("\27[94m%s\27[0m> ", syscall("getcwd"))
  local line = readline()
  parse(line .. "\n")
end
