require_relative 'config'
require 'socket'
require 'qos-lib'

class SignalReceiver

  attr_accessor :notifier

  def initialize(addr)
    @peer_ip,@peer_port = addr
    @token_lock = Mutex.new
    @token_ok = ConditionVariable.new
    @token_get = 0
  end

  def connect_peer
    @peer = TCPSocket.new(@peer_ip,@peer_port) 
    puts "Sender #{@peer_ip}:#{@peer_port} Connected"
  end

  def run_loop
    while @peer.gets
      data = $_.split
      delay = Time.now.to_f - data[1].to_f
      from = data[2]
      token = data[3].to_i || ''
      printf("[#{from}] %6s %s, Time delayed: %7.4fms\n",data[0],token,delay*1000) if @notifier.show_cmd
      if @notifier
        if data[0] =~ /STOP/i
          @notifier.send_stop(data[1].to_f)
        elsif data[0] =~ /GO/i
          @notifier.send_go(data[1].to_f)
        elsif data[0] =~ /ADD_TOKEN/i
          @notifier.send_token(token,data[1].to_f)
        elsif data[0] =~ /GIVE_TOKEN/i
          @token_lock.synchronize do
            @token_get += token
          end
          @token_ok.signal
        end
      end
    end
    # closed
  end

  def cleanup
    @peer.close
  end

  def get_token(min,max)
    #puts "Getting token: {#{min},#{max}}"
    @peer.puts "GET_TOKEN #{min} #{max} #{Time.now.to_f}"
    @token_ret = 0
    @token_lock.synchronize do
      while @token_get < min
        @token_ok.wait(@token_lock)
      end
      @token_ret = [@token_get,max].min
      @token_get -= @token_ret
    end
    @token_ret
  end

end

