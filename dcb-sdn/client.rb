#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'fileutils'
require 'qos-lib'

require 'packet_buffer'
require 'packet_handler'
require 'control_api' 

if CLIENT_RANDOM_FIXED_SEED
  srand(0)
end

$host = ARGV[1]
$port = ARGV[2].to_i
$host_ip = ARGV[3]
$size = ARGV[4].to_i
if !$host_ip
  puts "Must specify client IP"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [size]"
  exit
end
if $size <= 0
  puts "Size need to > 0"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [size]"
  exit
end

$pkt_buf = PacketBuffer.new($host_ip,$host,[$port],true)
holder_list = TARGET_HOSTS_ID[$host_ip].join(',') # who will you send?
$control_api = ControlAPI.new($host_ip,$host_ip,holder_list)
$pkt_buf.register_control_api($control_api)

# ///////////
# Control Loop
# ///////////
$thr_control = Thread.new do
  $control_api.run_main_loop
end

# ///////////
# Pkt Buffer: read loop
# ///////////
$thr_read = Thread.new do
  $pkt_buf.run_receive_loop
end

# ///////////
# Pkt Buffer: stop go loop
# ///////////
$thr_stop_go_loop = Thread.new do
  $pkt_buf.stop_go_check_loop
end

# ///////////
# Pkt Buffer: writer loop (for premature acks)
# ///////////
$thr_write  = Thread.new do 
  $pkt_buf.writer_loop($port) 
end

$peer = ActivePacketHandler.new($pkt_buf,$host,$port,$size)
$control_api.register_handler($peer)

$thr_port = Thread.new do
  $peer.run_loop
end


begin
  sleep
rescue SystemExit, Interrupt
  puts "\n關閉連線中..."
  $peer.cleanup
  puts "關閉Packet Handler..."
  $thr_port.join
  $pkt_buf.end_receive
  puts "關閉Packet Buffer..."
  $thr_read.exit
  puts "關閉Control API..."
  $control_api.close
  $thr_control.join
  puts "client結束"
  exit
end
