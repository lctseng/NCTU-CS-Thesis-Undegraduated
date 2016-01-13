#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'fileutils'
require 'qos-lib'

require 'common'
require 'sender_process'


$host = ARGV[1]
$port = ARGV[2].to_i
$host_ip = ARGV[3]
$command = ARGV[4]
$size = ARGV[5].to_i
if CLIENT_RANDOM_FIXED_SEED
  srand($port)
end
if !$host_ip
  puts "Must specify client IP"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [cmd] [size]"
  exit
end
if $size <= 0
  puts "Size need to > 0"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [cmd] [size]"
  exit
end

$sender = SenderProcess.connect($host,$port)
$id = $sender.id

interval = IntervalWait.new
delay = Timing.start
while true
  $sender.send("1"*PACKET_SIZE,0)
end

begin
  sleep
rescue SystemExit, Interrupt
  puts "\n關閉連線中..."
  puts "client結束"
  exit
end
