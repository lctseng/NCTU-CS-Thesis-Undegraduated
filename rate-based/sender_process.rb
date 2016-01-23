require_relative 'config'
require 'common'

require 'socket'
require 'thread'

class SenderProcess
 

  attr_accessor :id
  attr_accessor :target_sock
  attr_accessor :controller_sock
  attr_reader :dst_ip
  attr_reader :dst_port

  def self.connect(dst_ip,dst_port)
    s = new(true,dst_ip,dst_port)
    s.target_sock = UDPSocket.new
    s.target_sock.bind("0.0.0.0",dst_port)
    s.target_sock.connect(dst_ip,dst_port)
    s.connect_controller
    s
  end

  def self.bind_sock(sock,dst_ip,dst_port)
    s = new(false,dst_ip,dst_port)
    s.target_sock = sock
    s.connect_controller
    s
  end

  def initialize(active,dst_ip,dst_port)
    @active = active
    @start_time = Time.at(0)
    @counter = 0.0
    @speed = Speed.pkti(RATE_BASED_BASE_SPEED_PKTI)
    @dst_ip = dst_ip
    @dst_port = dst_port
    @id = "#{dst_ip}:#{dst_port}"
  end

  def connect_controller
    @controller_sock = TCPSocket.new(RATE_BASED_CTRL_ADDR,RATE_BASED_CTRL_PORT)
    # send register
    msg = ControlMessage.host(@id,ControlMessage::HOST_REGISTER)
    msg.send(@controller_sock,0)
  end

  def send(msg,flag)
    while @counter < 1.0
      # sleep for a while
      diff = Time.now - @start_time
      if diff >= RATE_BASED_SEND_INTERVAL
        # already very long, directly add
      else
        # need to wait :)
        sleep(RATE_BASED_SEND_INTERVAL - diff)
      end
      @start_time = Time.now
      @counter += @speed.pkti
    end
    @counter -= 1.0
    if @active
      @target_sock.send(msg,flag)
    else
      @target_sock.send(msg,flag,@dst_ip,@dst_port)
    end
  end

  def recv(n)
    @target_sock.recv(n)
  end

  def run_control_loop
    loop do
      msg = ControlMessage.recv(@controller_sock)
      last_spd = @speed.pkti
      last_used = last_spd - @counter
      @speed = Speed.pkti(msg.spd)
      new_spd = msg.spd
      if new_spd > last_spd
        # increase token
        @counter += new_spd - last_used
      else
        # limit counter
        @counter = [0,new_spd - last_used].max
      end
      printf("Speed: %7.4f Mbps\n",@speed.mbps)
    end
  end

  def close
    @controller_sock.close
  end

end



class ReceiverProcess
 

  attr_accessor :id
  attr_accessor :target_sock
  attr_reader :dst_ip
  attr_reader :dst_port

  def self.connect(dst_ip,dst_port)
    s = new(true,dst_ip,dst_port)
    s.target_sock = UDPSocket.new
    s.target_sock.bind("0.0.0.0",dst_port)
    s.target_sock.connect(dst_ip,dst_port)
    s
  end

  def self.bind_sock(sock,dst_ip,dst_port)
    s = new(false,dst_ip,dst_port)
    s.target_sock = sock
    s
  end

  def initialize(active,dst_ip,dst_port)
    @active = active
    @dst_ip = dst_ip
    @dst_port = dst_port
    @id = "#{dst_ip}:#{dst_port}"
  end
  
  def send(msg,flag)
    if @active
      @target_sock.send(msg,flag)
    else
      @target_sock.send(msg,flag,@dst_ip,@dst_port)
    end
  end
  
  def recv(n)
    @target_sock.recv(n)
  end
end
