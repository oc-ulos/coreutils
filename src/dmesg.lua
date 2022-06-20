--!lua

for _,line in ipairs(require'syscalls'.syslog()) do print(line) end
