--!lua

local argv = ...

local args, opts = require("getopt").getopt({
  options = {
    l = false, c = false, w = false, help = false
  },
  allow_finish = true,
  exit_on_bad_opt = true,
  help_message = "see '" .. argv[0] .. " --help' for more information.\n"
}, argv)

if #args == 0 then args[1] = "-" end

if opts.help then
  io.stderr:write(([[
usage: %s [-lcw] FILE ...
Print line, word, and character (byte) counts from all given FILEs.

Options:
  -l  Print line counts.
  -c  Print character counts.
  -w  Print word counts.

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(argv[0]))
  os.exit(1)
end

if not (opts.l or opts.w or opts.c) then
  opts.l = true
  opts.w = true
  opts.c = true
end

local function wc(file)
  local handle, err
  if file == "-" then
    handle = io.stdin
  else
    handle, err = io.open(file, "r")
    if not handle then
      return nil, err
    end
  end

  local data = handle:read("a")
  handle:close()

  local out = {}

  if opts.l then
    local last = 0
    local val = 0

    while true do
      local nex = data:find("\n", last)
      if not nex then break end
      val = val + 1
      last = nex + 1
    end

    out[#out+1] = tostring(val)
  end

  if opts.w then
    local last = 0
    local val = 0

    while true do
      local nex, nen = data:find("[ \n\t\r]+", last)
      if not nex then break end
      val = val + 1
      last = nen + 1
    end

    out[#out+1] = tostring(val)
  end

  if opts.c then
    out[#out+1] = tostring(#data)
  end

  return out
end

for i=1, #args, 1 do
  local ok, err = wc(args[i])
  if not ok then
    io.stderr:write("wc: ", args[i], ": ", err, "\n")
    os.exit(1)

  else
    io.write(table.concat(ok, " "), " ", args[i], "\n")
  end
end
