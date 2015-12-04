require_relative 'config'
require 'socket'
require 'qos-lib'

class SignalReceiver
  def initialize(pkt_buf,addr)
    @pkt_buf = pkt_buf
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
      printf("%6s, Time delayed: %7.4fms\n",data[0],delay*1000)
      if data[0] =~ /STOP/i
        @pkt_buf.send_stop
      elsif data[0] =~ /GO/
        @pkt_buf.send_go
      end
    end
    # closed
  end

  def cleanup
    @peer.close
  end

end

