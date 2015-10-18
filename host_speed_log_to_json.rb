#!/usr/bin/env ruby  
require 'json'
require_relative 'qos-info'

def process_port_log(port)
  filename = sprintf(HOST_LOG_NAME_FORMAT,port)
  if File.exist?(filename)
    host_id = port - 5000
    data = {}
    data[:name] = "h#{host_id}"
    array = []
    File.open(filename) do |f|
      while f.gets
        array << $_.to_i
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

