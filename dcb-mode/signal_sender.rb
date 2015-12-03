require_relative 'config'
require 'socket'
require 'qos-lib'

class SignalSender
  def initialize(receiver_ip)
    @receiver_ip = receiver_ip
    
  end

  def connect_receiver
    @receiver = TCPSocket.new(@receiver_ip,DCB_SIGNAL_SENDER_PORT) 
    puts "Receiver #{receiver_ip} Connected"
  end

end

