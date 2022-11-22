--!lua
-- Read /etc/fstab, and mount filesystems accordingly

local sys = require("syscalls")
local errx = require("posix.errno").errno
local handle = io.open("/etc/fstab")
if not handle then
  io.stderr:write("readfstab: Warning: no /etc/fstab\n")
  return sys.exit(0)
end

for line in handle:lines() do
  if #line > 0 and line:sub(1,1) ~= "#" then
    local dev, path = line:match("([^ ]+) +([^ ]+)")
    sys.mkdir(path)
    local ok, err = sys.mount(dev, path)

    if not ok then
      io.stderr:write(("readfstab: Failed mounting '%s' on '%s': %s\n")
        :format(dev, path, errx(err)))

    else
      io.stderr:write(("readfstab: Mounted '%s' on '%s'\n"):format(dev, path))
    end
  end
end

handle:close()
