#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'fileutils'
NO_TYPE_REQUIRED = true
require 'qos-lib'

require 'packet_buffer'
require 'packet_handler'
require 'signal_receiver'


if CLIENT_RANDOM_FIXED_SEED
  srand(0)
end

$host = ARGV[0]
$port = ARGV[1].to_i
$size = ARGV[2].to_i
if $size <= 0
  puts "Size need to > 0"
  exit
end

$pkt_buf = PacketBuffer.new($host,[$port],true)
$signal_recv = SignalReceiver.new([DCB_SDN_CTRL_ADDR,DCB_SDN_CTRL_PORT])
$signal_recv.notifier = $pkt_buf

$signal_recv.connect_peer


$thr_read = Thread.new do
  $pkt_buf.run_receive_loop
end

$thr_recv = Thread.new do
  begin
    $signal_recv.run_loop
  rescue IOError
  end
end


$peer = ActivePacketHandler.new($pkt_buf,$port,$size)
$peer.token_getter = $signal_recv

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
  $signal_recv.cleanup
  puts "關閉Signal Receiver..."
  $thr_recv.join
  $pkt_buf.end_receive
  puts "關閉Packet Buffer..."
  $thr_read.exit
  puts "client結束"
  exit
end
