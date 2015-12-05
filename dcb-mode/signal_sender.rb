require_relative 'config'
require 'socket'
require 'thread'
require 'qos-lib'

class SignalSender

  attr_reader :peer_lock
  attr_accessor :peers
  attr_reader :main_sock
  attr_accessor :originator

  def initialize
    @peers = []
    @peer_lock = Mutex.new
  end

  def bind_port(shift = 0)
    @main_sock = TCPServer.new("0.0.0.0",DCB_SIGNAL_SENDER_PORT + shift)  
  end
  
  def accept_client
    ready = IO.select([@main_sock]+@peers)
    ready[0].each do |sock|
      if sock == @main_sock
        new_sock = @main_sock.accept
        #puts "New receiver connected"
        if @originator
          case @originator.previous_state
          when :go
            new_sock.puts "GO #{Time.now.to_f} #{@originator.name}"
          when :stop
            new_sock.puts "STOP #{Time.now.to_f} #{@originator.name}"
          end
        end
        @peer_lock.synchronize do 
          @peers << new_sock
        end
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


  def notify_go(time = Time.now.to_f)
    @peer_lock.synchronize do 
      @peers.each do |peer|
        if peer.closed?
          @peers.delete(peer)
        else
          peer.puts "GO #{time} #{@originator.name}"
        end
      end
    end
  end

  def notify_stop(time = Time.now.to_f)
    @peer_lock.synchronize do 
      @peers.each do |peer|
        if peer.closed?
          @peers.delete(peer)
        else
          peer.puts "STOP #{time} #{@originator.name}"
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



