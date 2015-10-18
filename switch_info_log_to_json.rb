#!/usr/bin/env ruby  
require 'json'
require_relative 'qos-info'

def process_port_log(port)
  filename = sprintf(SWITCH_LOG_NAME_FORMAT,port)
  if File.exist?(filename)
    data_total_spd = []
    data_avg_spd = []
    data_current_util = []
    data_recent_util = []
    data_total_util = []
    data_qlen = []
    File.open(filename) do |f|
      while f.gets
        data = $_.split
        timestamp = data.shift.to_f
        total_spd, avg_spd, current_util, recent_util, total_util, qlen =  data.collect{|n| n.to_i}
        data_total_spd << [timestamp,total_spd]
        data_avg_spd << [timestamp,avg_spd]
        data_current_util << [timestamp,current_util]
        data_recent_util << [timestamp,recent_util]
        data_total_util << [timestamp,total_util]
        data_qlen << [timestamp,qlen]
      end
    end
    ["total_spd","avg_spd","current_util","recent_util","total_util","qlen"].each do |type|
      eval <<-DOC
        File.open(sprintf(SWITCH_LOG_NAME_JSON_FORMAT,"#{type}","#{port}"),'w') do |f|
          array = data_#{type}
          data = {
            name: "#{port}",
            type: "#{type}",
            size: array.size,
            data: array
          }
          f.puts data.to_json
        end
      DOC
    end
  end
end


for port in QOS_INFO.keys
  process_port_log(port)
end

