#!/usr/bin/env ruby 
pack_name = ARGV[0]
if !pack_name || pack_name.empty?
  puts "[Usage] pack_log.rb <log name>"
  exit
end
`tar -cf #{pack_name}.log.tar *.out`
`scp #{pack_name}.log.tar lctseng@bsd5.cs.nctu.edu.tw:~/public_html/files/src_tar/`
