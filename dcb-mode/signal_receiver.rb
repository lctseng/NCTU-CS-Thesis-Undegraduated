require_relative 'config'
require 'socket'
require 'qos-lib'

class SignalReceiver

  attr_accessor :notifier

  def initialize(addr)
    @peer_ip,@peer_port = addr
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
      printf("[#{from}] %6s, Time delayed: %7.4fms\n",data[0],delay*1000) if @notifier.show_cmd
      if @notifier
        if data[0] =~ /STOP/i
          @notifier.send_stop(data[1].to_f)
        elsif data[0] =~ /GO/
          @notifier.send_go(data[1].to_f)
        end
      end
    end
    # closed
  end

  def cleanup
    @peer.close
  end

end

