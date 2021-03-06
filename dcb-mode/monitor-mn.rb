#!/usr/bin/env ruby 

require_relative 'config'

require 'socket'
NO_TYPE_REQUIRED = true
require 'qos-info'
require 'signal_sender'
require 'signal_receiver'


$DEBUG = true

# 傳送資料間隔
MONITOR_INTERVAL = 0.01
MONITOR_DETECT_INTERVAL = MONITOR_INTERVAL / 10.0
$max_spd = MAX_SPEED / UNIT_MEGA

# 紀錄最後長度
$last_len = 0
# 要監測的s
$sw = ARGV[0]
# 網卡編號 
$eth = ARGV[1]
# 要監測的queue
$qid = $eth.to_i + 1
# Port
$port = "#{$sw}-eth#{$eth}"

$q_data = nil

# 取得queue length
def get_queue_len(qid)
  len = -1
  spd = 0
  sent = 0
  IO.popen("tc -s class show dev #{$port} classid 1:#{qid}") {|result|
    str = result.read
    if str =~ /backlog \d+b (\d+)p/i
      len =  $1.to_i
      # 取得速度
      str =~ /ceil (\d+)Mbit/i
      spd = $1.to_i
    else
      puts "找不到Queue資訊"
    end
    if str =~ /Sent \d+ bytes (\d+) pkt/i
      sent = $1.to_i
    end
  }
  {len: len,spd: spd,sent: sent}
end
# 更改queue最大速度
def set_max_speed(speed)
  return if defined?(NO_SPEED_LIMIT_FOR) && NO_SPEED_LIMIT_FOR.include?($port)
  IO.popen "tc class change dev #{$port} classid 1:#{$qid} htb rate 12Kbit ceil #{speed}Mbit"
end




$signal_sender.bind_port(dcb_get_sw_port_shift($sw))
thr_signal_accept = run_accept_thread

$signal_receiver = SignalReceiver.new(dcb_get_upstream(:switch,$sw))
$signal_receiver.connect_peer


class SignalPasser

  attr_reader :previous_state
  attr_reader :recv
  attr_reader :send

  def initialize(recv,send)
    @recv = recv
    @send = send
    @recv.notifier = self
    @send.originator = self
  end

  def send_go(time)
    #puts "#{$sw}: GO!"
    #sleep 0.001
    @send.notify_go(time)
    #set_max_speed(800)
    @previous_state = :go
  end

  def send_stop(time)
    #puts "#{$sw}: STOP!"
    #sleep 0.001
    @send.notify_stop(time)
    #if @previous_state != :stop
    #  if $q_data[:len] > 200
    #    set_max_speed(800)
    #  else
    #    set_max_speed(800)
    #  end
    #end
    @previous_state = :stop
  end

  def temp_stop
    if @previous_state == :go && !@temp_stopped
      @temp_stopped = true
      @previous_state = :stop
      @send.notify_stop
      set_max_speed(20)
      puts "Temp STOP!"
    end
  end

  def resume_go
    if @temp_stopped
      @temp_stopped = false
      #if @previous_state == :go
        @send.notify_go
        set_max_speed(800)
      #end
      puts "Temp Resume!"
    end
  end

  def name
    "#{$sw}"
  end

  def show_cmd
    false
  end
end

$signal_passer = SignalPasser.new($signal_receiver,$signal_sender)

thr_signal_read = Thread.new do
  $signal_receiver.run_loop
end

last_sent = 0
# 不斷取得queue len
begin
  last_time = Time.now
  loop do
    # Timing compute
    last_time = Time.now
    $q_data = data =  get_queue_len($qid)
    len = data[:len]
    sent_diff = data[:sent] - last_sent
    last_sent = data[:sent]
    if len >= 500
      puts "在#{Time.now.to_f}發起！" if DEBUG_TIMING
    end

    if len > 200
      #$signal_passer.temp_stop
    else
      #$signal_passer.resume_go
    end
    if len >= 0 
      # 畫圖
      bar_len = (len / 20.0).ceil
      printf("%5d,速度上限：%3d Mbits, 區間已送出: %4d,Queue:%s\n",len,data[:spd],sent_diff,"|"*bar_len) if MONITOR_SHOW_INFO
    end
    if data[:spd] <= 25 && len >= 200
      #set_max_speed(100)
    end
    sleep MONITOR_INTERVAL

  end
rescue SystemExit, Interrupt
  $controller_sock.puts "close"
  $controller_sock.close
end
