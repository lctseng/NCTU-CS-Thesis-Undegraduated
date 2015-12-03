require_relative 'config'
require 'socket'
require 'thread'
require 'qos-lib'

class SignalReceiver

  attr_reader :sender_lock
  attr_accessor :sneders
  attr_reader :main_sock

  def initialize
    @main_sock = TCPServer.new("0.0.0.0",DCB_SIGNAL_SENDER_PORT)  
    @senders = []
    @sender_lock = Mutex.new
  end
  
  def accept_client
    @sender_lock.synchronize do 
      @senders << @main_sock.accept
    end
    puts "New sender connected"
  end


end

$signal_recv = SignalReceiver.new

def run_accept_thread
  thr = Thread.new do 
    loop do
      $signal_recv.accept_client
    end
  end
end

