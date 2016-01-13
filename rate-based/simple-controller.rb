#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'qos-lib'
require 'common'

$DEBUG = true
class SenderProcessInfo
  attr_accessor :id
  attr_accessor :sock
  attr_accessor :spd
  attr_accessor :arrive_time
  attr_accessor :data_lock

  def initialize(id,sock)
    @id = id
    @sock = sock
    @spd = Speed.pkti(RATE_BASED_BASE_SPEED_PKTI) 
    @arrive_time = Time.now
    @data_lock = Mutex.new
  end

  def age
    Time.now - @arrive_time
  end

end

class SwitchPortInfo
  attr_accessor :id
  attr_accessor :sock
  attr_accessor :spd
  attr_accessor :spd_limit
  attr_accessor :qlen
  attr_accessor :data_lock

  def initialize(id,sock)
    @id = id
    @sock = sock
    @spd = Speed.pkti(0) # speed on it
    @spd_limit = Speed.mbps(MAX_SPEED_M) 
    @data_lock = Mutex.new
    @qlen = 0
  end
end



# =============================
# Globals
# ============================= 

# for all clients
$senders_by_id = {}
$switches_by_id = {}
$switches_by_sock = {}

$switches_sock_list = []


$senders_id_lock = Mutex.new
$switches_id_lock = Mutex.new
$switches_sock_lock = Mutex.new


# main sockets
$main_sock = TCPServer.new(RATE_BASED_CTRL_ADDR,RATE_BASED_CTRL_PORT)

# =============================
# Create threads
# =============================

# For accept new clients 
$thr_accept = Thread.new do
  loop do
    new_sock = $main_sock.accept
    # read data for identify
    msg = ControlMessage.recv(new_sock)
    case msg.src_type
    when ControlMessage::TYPE_HOST
      info = SenderProcessInfo.new(msg.id,new_sock)
      $senders_id_lock.synchronize do
        $senders_by_id[msg.id] = info
      end
    when ControlMessage::TYPE_SWITCH
      info = SwitchPortInfo.new(msg.id,new_sock)
      $switches_id_lock.synchronize do
        $switches_by_id[msg.id] = info
      end
      $switches_sock_lock.synchronize do
        $switches_by_sock[new_sock] = info
      end
      $switches_sock_list << new_sock
    end

  end
end









# Switch Reader 
$thr_sw_reader = Thread.new do
  while $switches_sock_list.empty?
    sleep 0.1
  end
  loop do
    ready = IO.select($switches_sock_list)
    ready[0].each do |sock|
      info = $switches_by_sock[sock]
      # read report
      msg = ControlMessage.recv(sock)
      info.spd = Speed.pkti(msg.spd)
      info.qlen = msg.qlen
    end
  end
end


# For monitoring
$thr_monitor = Thread.new do
  interval = IntervalWait.new
  loop do
    interval.sleep RATE_BASED_SHOW_INTERVAL
    puts "========================"
    STARTING_ORDER.each do |id|
      info = $switches_by_id[id]
      next if !info
      printf("[%s] 速:%7.4f Mbps, 限: %7.4f Mbps, Q: %4d \n",info.id,info.spd.mbps,info.spd_limit.mbps,info.qlen)
    end
  end
end







# =============================
# main thread: sleep
# =============================
sleep









