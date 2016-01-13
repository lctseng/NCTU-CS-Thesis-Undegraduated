#!/usr/bin/env ruby 
require_relative 'config'
require 'qos-info'

$base_time = Time.now.to_f

# Find the smallest time amount the files
# Hosts
def filter_host(port)
  filename = sprintf(HOST_LOG_NAME_FORMAT,port)
  if File.exist?(filename)
    File.open(filename) do |f|
      while f.gets
        if ~ /^(\d+(\.\d+)?) /i
          time = $_.split.shift.to_f
          $stderr.puts "host:#{port}:#{time}"
          $base_time = [time,$base_time].min
          break
        end
      end
    end
  end
end
# Switches
def filter_switch(port)
  filename = sprintf(SWITCH_LOG_NAME_FORMAT,port)
  if File.exist?(filename)
    File.open(filename) do |f|
      while f.gets
        if ~ /^(\d+(\.\d+)?) /i
          time = $_.split.shift.to_f
          $stderr.puts "switch #{port}:#{time}"
          $base_time = [time,$base_time].min
          break
        end
      end
    end
  end
end


# Hosts
for port in 5002..5008
  filter_host(port)
end
# Switches
for port in QOS_INFO.keys
  filter_switch(port)
end
# Output
$stderr.puts "Time base: #{$base_time}"
puts $base_time
