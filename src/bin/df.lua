#!/usr/bin/env lua
-- df

local getopt = require("getopt")

local args, opts, usage = getopt.process {
  { "print sizes in powers of 1024", false, "h", "human-readable" },
  { "print sizes in powers of 1000", false, "H", "si" },
  { "use POSIX output format", false, "P", "portability" },
  { "only show filesystem types matching TYPE", "TYPE", "t", "type" },
  { "print filesystem type", false, "T", "print-type" },
  { "exclude filesystem types matching TYPE", "TYPE", "x", "exclude-type" },
  { "display this help message and exit", false, "help" },
  exit_on_bad_opt = true,
  help_message = "pass '--help' for help\n",
  args = arg,
}


