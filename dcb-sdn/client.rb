#!/usr/bin/env ruby 

require_relative 'config'
require 'qos-lib'


$host = ARGV[1]
$port = ARGV[2].to_i
$host_ip = ARGV[3]

start = Time.now
File.open("pattern/client_#{$port}.pattern") do |f|
  while line = f.gets
    data = line.split
    size = (data[1].to_f/PACKET_SIZE).ceil * PACKET_SIZE
    case data[0] # command
    when "read","write"
      puts line
      fork do
        Process.exec("./client_traffic_executer.rb __last__ #{$host} #{$port} #{$host_ip} #{data[0]} #{size} #{data[2]}")
      end
      Process.waitall
    when "sleep"
      sleep data[1].to_f
    end
  end
end
puts "Client exiting, Elapse: #{Time.now - start}"
