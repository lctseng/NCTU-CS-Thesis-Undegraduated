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
    @peer_data = {}
    @reverse_peer_data = {}
    @peer_lock = Mutex.new
    @peer_data_lock = Mutex.new
  end

  def bind_port(port)
    @main_sock = TCPServer.new("0.0.0.0",port)  
  end
  
  def accept_client
    ready = IO.select([@main_sock]+@peers)
    ready[0].each do |sock|
      if sock == @main_sock
        new_sock = @main_sock.accept
        #puts "New receiver connected"
        addr = new_sock.peeraddr(false)
        #id = "#{addr[3]}:#{addr[1]}"
        id = addr[3]
        simple = addr[3] != '172.16.0.1'
        @peer_lock.synchronize do 
          @peers << new_sock
          @peer_data[new_sock] = {min: 0,max: 0,id: id,addr: addr,simple: simple}
          @reverse_peer_data[id] = new_sock
        end
        if @originator
          @originator.new_receiver
        end

      else # peer sock
        str = sock.recv(PACKET_SIZE)
        if str.empty?
          #puts "Receiver disconnected"
          @peers.delete(sock)
        else
          #puts "Receiver message:#{str}"
          if str =~ /GET_TOKEN (\d+) (\d+) (.+)/i
            min = $1.to_i
            max = $2.to_i
            time = $3.to_f
            data = @peer_data[sock]
            @peer_data_lock.synchronize do
              data[:min] = min
              data[:max] = max
            end
            @originator.new_token_request(data[:id],min,max,time)
          else

          end
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

  
  def notify_token(token,time = Time.now.to_f)
    @result = false
    @peer_lock.synchronize do 
      @peers.each do |peer|
        if peer.closed?
          @peers.delete(peer)
        else
          @result = true
          peer.puts "ADD_TOKEN #{time} #{@originator.name} #{token}"
        end
      end
    end
    @result
  end

  def dispatch_token_id(id,send,time)
    sock = @reverse_peer_data[id]
    if !sock.closed?
      @peer_data_lock.synchronize do
        data = @peer_data[sock]
        data[:min] = [data[:min] - send,0].max
        data[:max] -= send
      end
      sock.puts "GIVE_TOKEN #{time} #{@originator.name} #{send}"
    else
      remove_peer(sock)
    end
  end

  def remove_peer(sock)
    @peer_data.delete(sock)
  end

  def dispatch_token(free,time)
    #puts "Dispatching Token, free = #{free}"
    return 0 if free == 0
    return free if free < 100
    total_need = 0.0
    @peer_data_lock.synchronize do
      @peer_data.each_value do |data|
        total_need += data[:min]
      end
    end
    #puts "==>Total need = #{total_need}"
    return free if total_need == 0
    @peer_data.each do |peer,data|
      if !peer.closed?
        if free >= data[:min] && data[:max] > 0
          dispatch = ((data[:min] / total_need)*free).ceil
          send = [data[:max],dispatch].min
          @peer_data_lock.synchronize do
            data[:min] = [data[:min] - send,0].max
            data[:max] -= send
          end
          peer.puts "GIVE_TOKEN #{time} #{@originator.name} #{send}"
          free -= send
          #puts "Giving Token: #{send}, remain = #{free}"
          break if free == 0
        end
      else
        @peer_data.delete(peer)
      end
    end
    return free

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



