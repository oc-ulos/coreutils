-- Read /etc/fstab, and mount filesystems accordingly

local sys = require("syscalls")
local errx = require("errors").err
local handle = io.open("/etc/fstab")

for line in handle:lines() do
  if #line > 0 and line:sub(1,1) ~= "#" then
    local dev, path = line:match("([^ ]+) +([^ ]+)")
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
