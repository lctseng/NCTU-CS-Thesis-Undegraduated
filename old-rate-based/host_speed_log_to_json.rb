#!/usr/bin/env ruby  
require_relative 'confg'
require 'json'
NO_TYPE_REQUIRED = true 
require 'qos-info'
TIME_BASE = ARGV[1].to_f

def process_port_log(port)
  filename = sprintf(HOST_LOG_NAME_FORMAT,port)
  if File.exist?(filename)
    host_id = port - 5000
    data = {}
    data[:name] = "h#{host_id}"
    array = []
    File.open(filename) do |f|
      while f.gets
        sub_data = $_.split
        sub_data[0] = sub_data[0].to_f - TIME_BASE
        sub_data[1] = sub_data[1].to_i
        array << sub_data
      end
    end
    data[:size] = array.size
    data[:data] = array
    File.open(sprintf(HOST_LOG_NAME_JSON_FORMAT,port),'w') do |f|
      f.puts data.to_json
    end
  end
end


for port in 5002..5008
  process_port_log(port)
end

