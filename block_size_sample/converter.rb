#!/usr/bin/env ruby 
filename = ARGV[0]

MAX_DATA_SIZE = 1500
PACKET_SIZE = 1400

f = File.open(filename)
raw_data = []
while f.gets
  raw_data << $_.to_f
end
puts "Raw size:#{raw_data.size}"
if raw_data.size > MAX_DATA_SIZE
  data = []
  MAX_DATA_SIZE.times do |i|
    index = rand(raw_data.size)
    data << raw_data[index]
    raw_data.delete_at index
  end
else
  data = raw_data
end
print '['
print data.collect{|n| (n/1400.0).ceil}.join(", ")
print "]\n"

