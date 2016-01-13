require_relative 'config'
require 'common'

require 'socket'
require 'thread'

class SenderProcess
 

  attr_accessor :id
  attr_accessor :target_sock
  attr_accessor :controller_sock

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
    @start_time = nil
    @counter = 0
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
    @start_time = Time.now if @start_time.nil?
    @counter += 1
    if @speed <= @counter #@counter >= @speed
      # sleep for a while
      if @start_time
        diff = Time.now - @start_time
        time = RATE_BASED_SEND_INTERVAL - diff
      else
        time = 0
      end
      sleep time if time > 0
      @counter = 0
      @start_time = Time.now
    end
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
