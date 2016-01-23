#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'qos-lib'
require 'common'

class SenderProcessInfo
  attr_accessor :id
  attr_accessor :sock
  attr_accessor :spd
  attr_accessor :arrive_time
  attr_accessor :data_lock
  attr_accessor :last_update

  def initialize(id,sock)
    @id = id
    @sock = sock
    @spd = Speed.pkti(RATE_BASED_BASE_SPEED_PKTI) 
    @arrive_time = Time.now
    @data_lock = Mutex.new
    @last_update = Time.now
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
  attr_accessor :spd_assigned
  attr_accessor :qlen
  attr_accessor :data_lock

  def initialize(id,sock)
    @id = id
    @sock = sock
    @spd = Speed.pkti(0) # speed on it, by counter
    @spd_assigned = Speed.pkti(0) # by controller assgined senders
    @spd_limit = Speed.mbps(MAX_SPEED_M) 
    @data_lock = Mutex.new
    @qlen = 0
  end
end

# =============================
# Routines
# ============================= 



def redeem_speed_from(sender_process)
  $switches_speed_assign_lock.synchronize do
  value = sender_process.spd.data
  flows = PACKET_FLOWS_SW_ONLY[sender_process.id]
  flows.each do |port|
    sw_info = $switches_by_id[port]
    sw_info.data_lock.synchronize do
      sw_info.spd_assigned.data -= value
    end
  end
  end
end


def redistribute_speed_passing_flow(flows)
  # how collect senders passing this port
  senders = {}
  flows.each do |port|
    passing_sender_ids = SWITCH_PORT_PASSING_HOST[port]
    passing_sender_ids.each do |id|
      if !senders.has_key?(id)&& $senders_by_id.has_key?(id)
        senders[id] = $senders_by_id[id]
      end
    end
  end
  senders.each_value do |sender|
    assign_max_speed_for(sender)
  end
end

# Remove a sender process
def remove_sender_process(sender_process)
  # Remove Entry
  $senders_id_lock.synchronize do
    $senders_by_id.delete(sender_process.id)
    $senders_id_list.delete(sender_process.id)
  end
  $senders_sock_lock.synchronize do
    $senders_by_sock.delete(sender_process.sock)
    $senders_sock_list.delete(sender_process.sock)
  end
  # Redeem speed 
  redeem_speed_from(sender_process)
  # Redistribute
  flows = PACKET_FLOWS_SW_ONLY[sender_process.id]
  redistribute_speed_passing_flow(flows)
end


# add assign speed for switches
def add_assign_speed_for_flows(flows,speed)
  flows.each do |port|
    sw_info = $switches_by_id[port]
    sw_info.data_lock.synchronize do
      sw_info.spd_assigned += speed
    end
  end
end

# add a speed this sender process
def add_speed_for(sender_process,speed)
  # final speed minima is RATE_BASED_BASE_SPEED_PKTI
  sender_process.data_lock.synchronize do
    final_speed = sender_process.spd + speed
    if final_speed < RATE_BASED_BASE_SPEED_PKTI # lower than min
      speed = -(sender_process.spd - Speed.pkti(RATE_BASED_BASE_SPEED_PKTI))
      sender_process.spd.data = RATE_BASED_BASE_SPEED_PKTI
    else
      sender_process.spd = final_speed
    end
  end
  flows = PACKET_FLOWS_SW_ONLY[sender_process.id]
  add_assign_speed_for_flows(flows,speed)
  msg = ControlMessage.controller(ControlMessage::HOST_CHANGE)
  msg.spd = sender_process.spd.pkti
  begin
    msg.send(sender_process.sock,0)
  rescue
    # The host is closed
    # Remove host - moved to single removing routine
    # remove_sender_process(sender_process)
  end
end


# assign max path speed 
# will collect path switch port
def assign_max_speed_for(sender_process)
  $switches_speed_assign_lock.synchronize do
    flows = PACKET_FLOWS_SW_ONLY[sender_process.id]
    max_spd = Speed.mbps(MAX_SPEED_M)
    can_use = max_spd
    flows.each do |port|
      sw_info = $switches_by_id[port]
      remain = max_spd - sw_info.spd_assigned
      if remain < can_use
        can_use = remain
      end
    end
    can_use *= RATE_BASED_ASSIGN_RATE
    add_speed_for(sender_process,can_use)
  end

end


def apply_host_speed_change_data(host_change)
  $switches_speed_assign_lock.synchronize do
  now = Time.now
  host_change.each do |id,change|
    info = $senders_by_id[id]
    if info && now - info.last_update > 0.05
      info.last_update = now
      add_speed_for(info,change)
    end
  end
  end
end

# =============================
# Globals
# ============================= 

# for all clients
$senders_by_id = {}
$switches_by_id = {}
$switches_by_sock = {}
$senders_by_sock = {}

$senders_sock_list = []
$switches_sock_list = [] # will not remove entry

$senders_id_list = []
$switches_id_list = []


$senders_id_lock = Mutex.new
$switches_id_lock = Mutex.new
$switches_sock_lock = Mutex.new
$senders_sock_lock = Mutex.new

$switches_speed_assign_lock = Mutex.new


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
        $senders_id_list << msg.id
      end
      $senders_sock_lock.synchronize do
        $senders_by_sock[new_sock] = info
        $senders_sock_list << new_sock
      end
      flows = PACKET_FLOWS_SW_ONLY[msg.id]
      add_assign_speed_for_flows(flows,info.spd)
      assign_max_speed_for(info)

    when ControlMessage::TYPE_SWITCH
      info = SwitchPortInfo.new(msg.id,new_sock)
      $switches_id_lock.synchronize do
        $switches_by_id[msg.id] = info
      end
      $switches_sock_lock.synchronize do
        $switches_by_sock[new_sock] = info
      end
      $switches_sock_list << new_sock
      $switches_id_list << msg.id
    end

  end
end



# Switch Scan
$thr_sw_scan = Thread.new do
  interval = IntervalWait.new
  loop do
    interval.sleep RATE_BASED_SWITCH_SCAN_INTERVAL
    # compute speed change for each host(difference)
    # change will keep the lowest one
    host_change = {}
    $switches_id_list.each do |sw_id|
      sw_info = $switches_by_id[sw_id]
      hosts = SWITCH_PORT_PASSING_HOST[sw_id] & $senders_id_list
      bias = false # whether to divide speed equally
      # Speed for queue
      if sw_info.qlen < 50 #&& (sw_info.spd_limit - sw_info.spd_assigned).pkti > 0.5
        # add some
        change_spd = Speed.pkti(0.5)
        bias = false
      elsif sw_info.qlen >= 100
        # decrease some
        change_spd = Speed.pkti(-0.5)
        bias = true
      else
        change_spd = Speed.pkti(0)
      end
      # Speed for Limit, must bias
      diff_spd = sw_info.spd_limit - sw_info.spd_assigned
      if diff_spd.pkti < -0.5
        # decrease some
        change_spd = [diff_spd,change_spd].min
        bias = true
        #puts "Limit Diff: #{diff_spd.mbps}"
        #puts "Limit change: #{change_spd.mbps}"
      end
      if bias
        total_speed = hosts.inject(0) {|r,host_id| r += $senders_by_id[host_id].spd.pkti}
      else
        divided_change_spd = change_spd / hosts.size
      end
      hosts.each do |host_id|
        if bias
          host_change_spd = change_spd * ($senders_by_id[host_id].spd.pkti / total_speed)
        else
          host_change_spd = divided_change_spd 
        end
        if !host_change.has_key?(host_id) || host_change[host_id] > host_change_spd
          host_change[host_id] = host_change_spd
        end
      end
    end # end each switch
    #puts "Host changes:#{host_change.inspect}"
    apply_host_speed_change_data(host_change)
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


# Sender Reader 
$thr_sender_reader = Thread.new do
  loop do
    while $senders_sock_list.empty?
      sleep 0.1
    end
    ready = IO.select($senders_sock_list,[],[],0.01)
    next if !ready
    ready[0].each do |sock|
      info = $senders_by_sock[sock]
      remove_sender_process(info)
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
      printf("[%s] 速:%9.4f Mbps, 限: %9.4f Mbps, Assigned: %9.4f Mbps, Q: %4d \n",info.id,info.spd.mbps,info.spd_limit.mbps,info.spd_assigned.mbps,info.qlen)
    end
  end
end







# =============================
# main thread: sleep
# =============================
sleep









