--!lua

local pwd = require("posix.pwd")
local grp = require("posix.grp")
local stat = require("posix.sys.stat")
--local unistd = require("posix.unistd")
local argv = ...

local help = ([[
usage: %s [options] LOGIN
   or: %s -D
   or: %s -D [options]

options:
  -h, --help                show this help message
  -b, --base-dir BASE_DIR   base for the new account's home directory
  -c, --comment COMMENT     GECOS field of the new account
  -D, --defaults            print defaults
  -d, --home-dir HOME_DIR   the new account's home directory
  -g, --gid GROUP           group ID for the new account
  -u, --uid UID             user ID for the new account
  -s, --shell SHELL         shell to use for the new account
  -m, --create-home         create the user's home directory
  -N, --no-user-group       do not create a group with the same name

Copyright (c) 2022 ULOS Developers under the GNU GPLv3.
]]):format(argv[0], argv[0], argv[0])

local args, opts = require("getopt").getopt({
  options = {
    h = false, help = false,
    b = true, ["base-dir"] = true,
    c = true, comment = true,
    D = false, defaults = false,
    d = true, ["home-dir"] = true,
    g = true, gid = true,
    u = true, uid = true,
    s = true, shell = true,
    m = false, ["create-home"] = false,
    N = false, ["no-user-group"] = false
  },
  finish_after_arg = true,
  exit_on_bad_opt = true,
  help_message = "see '"..argv[0].." --help' for details\n"
}, argv)

opts.h = opts.h or opts.help
opts.D = opts.D or opts.defaults

if (#args == 0 and not opts.D) or opts.h or not (opts.D or opts.u) then
  io.stderr:write(help)
  os.exit(1)
end

-- TODO: are these saved on-disk somewhere?
local defaults = {
  uid = 0,
  group = 0,
  comment = "",
  base = "/",
  home = "/home",
  inactive = -1,
  shell = "/bin/sh.lua",
  skel = "/etc/skel",
}

for ent in pwd.getpwent do
  defaults.uid = math.max(defaults.uid, ent.pw_uid + 1)
  defaults.group = math.max(defaults.group, ent.pw_gid + 1)
end
pwd.endpwent()

if #args == 0 and opts.D then
  for k,v in pairs(defaults) do
    print(k.."="..v)
  end
  os.exit(0)
end

local login = args[1]

opts.b = opts.b or opts["base-dir"] or defaults.base
opts.c = opts.c or opts.comment or defaults.comment
opts.d = opts.d or opts["home-dir"] or defaults.home.."/"..login
opts.u = tonumber(opts.u or opts.uid) or defaults.uid
opts.g = tonumber(opts.g or opts.gid) or defaults.group
opts.s = opts.s or opts.shell or defaults.shell
opts.m = opts.m or opts["create-home"]
opts.N = opts.N or opts["no-user-group"]

if not stat.stat(opts.s) then
  io.stderr:write(argv[0], ": that shell does not exist\n")
  os.exit(1)
end

if pwd.getpwnam(login) then
  io.stderr:write(argv[0], ": that user already exists\n")
  os.exit(1)
end

local new = {
  pw_name = login,
  pw_passwd = "",
  pw_uid = opts.u,
  pw_gid = opts.g,
  pw_gecos = opts.c,
  pw_dir = opts.d,
  pw_shell = opts.s
}

pwd.update_passwd(new)

if not opts.N then
  local ok, err = grp.update_group({
    gr_name = login,
    gr_gid = opts.g,
    gr_mem = {login}
  })

  if not ok then
    io.stderr:write("useradd: update_group failed: ", err, "\n")
  end
end

if opts.m then
  local ok = os.execute("mkdir -p " .. new.pw_dir)
  if not ok then
    io.stderr:write("useradd: failed creating home directory\n")
    os.exit(1)
  end
end
