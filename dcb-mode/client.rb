#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'fileutils'
require 'qos-lib'

require 'packet_buffer'
require 'packet_handler'


if CLIENT_RANDOM_FIXED_SEED
  srand(0)
end

$host = ARGV[0]
$port = ARGV[1].to_i


$pkt_buf = PacketBuffer.new($host,[$port],true)
thr_port = Thread.new do
  peer = ActivePacketHandler.new($pkt_buf,$port)
  peer.run_loop
end

begin
  sleep
rescue SystemExit, Interrupt
  puts "client結束"
end
