require_relative 'config'
require 'socket'
require 'thread'
require 'qos-lib'

class SignalSender

  attr_reader :sender_lock
  attr_accessor :sneders
  attr_reader :main_sock

  def initialize
    @peers = []
    @peer_lock = Mutex.new
  end

  def bind_port
    @main_sock = TCPServer.new("0.0.0.0",DCB_SIGNAL_SENDER_PORT)  
  end
  
  def accept_client
    ready = IO.select([@main_sock]+@peers)
    ready[0].each do |sock|
      if sock == @main_sock
        new_sock = @main_sock.accept
        @peer_lock.synchronize do 
          @peers << new_sock
        end
        #puts "New receiver connected"
      else # peer sock
        str = sock.recv(PACKET_SIZE)
        if str.empty?
          #puts "Receiver disconnected"
          @peers.delete(sock)
        else
          puts "Receiver message:#{str}"
        end
      end
    end
  end


  def notify_go
    @peer_lock.synchronize do 
      @peers.each do |peer|
        if peer.closed?
          @peers.delete(peer)
        else
          peer.puts "GO #{Time.now.to_f}"
        end
      end
    end
  end

  def notify_stop
    @peer_lock.synchronize do 
      @peers.each do |peer|
        if peer.closed?
          @peers.delete(peer)
        else
          peer.puts "STOP #{Time.now.to_f}"
        end
      end
    end

  end

end

$signal_sender = SignalSender.new

def run_accept_thread
  thr = Thread.new do 
    loop do
      $signal_sender.accept_client
    end
  end
end



