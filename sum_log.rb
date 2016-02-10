#!/usr/bin/env ruby
filenames = ARGV[0]
if !filenames
  puts "[Usage] sum_log.rb <file1,file2,...>"
  exit
end

filenames = filenames.split(",")
data = {}
data_valid = {}
data_valid.default = 0
valid_req = 0
filenames.each do |filename|
  File.open(filename) do |f|
    valid_req += 1
    while f.gets
      arr = $_.split
      time = (arr[0].to_f / 0.5).round * 0.5
      value = arr[1].to_f
      if data.has_key? time
        data[time] += value
      else
        data[time] = value
      end
      data_valid[time] += 1
    end
  end
end


# Outout 
data.keys.sort.each do |time|
  if data_valid[time] == valid_req
    puts "#{time} #{data[time]}"
  else
    $stderr.puts "INVALID TIME: #{time}"
  end
end
