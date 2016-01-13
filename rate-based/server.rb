#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
NO_TYPE_REQUIRED = true if !defined? NO_TYPE_REQUIRED
require 'qos-lib'
require 'common'
require 'sender_process'


sock = UDPSocket.new
sock.bind("0.0.0.0",5003)
sender = SenderProcess.bind_sock(sock,"172.16.0.3",5003)
while true
  msg = sender.recv(PACKET_SIZE)
end
