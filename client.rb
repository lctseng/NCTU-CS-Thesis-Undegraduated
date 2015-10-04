#!/usr/bin/env ruby 

require 'socket'
require_relative 'host-info'
require_relative 'qos-info'

$DEBUG = true

PACKET_SIZE = 1450
SEND_INTERVAL = 0.001
if ENABLE_ASSIGN
  INIT_SPEED_PER_SECOND = 0
else
  INIT_SPEED_PER_SECOND = 8*1000 # 80 Kbit (10 KB)
end
INIT_SPEED_PER_INTERVAL = INIT_SPEED_PER_SECOND * SEND_INTERVAL





$host = ARGV[0]
$port = ARGV[1].to_i





def connect_server
  $sender = UDPSocket.new
  $sender.connect($host,$port)
end
def connect_controller
  puts "連接Controller中..."
  $controller_sock = TCPSocket.new CONTROLLER_IP_HOST,CONTROLLER_PORT
  $controller_sock.puts "host 0"
  puts "Controller已連接！"

end

def clear_variables
  $running = true
  $speed = INIT_SPEED_PER_INTERVAL
  $total_send = 0
  $interval_send = 0
  $speed_report = 0
  $delay_send = 0
end

def reset_time
  $next_stop_time = Time.now + rand(CLIENT_RANDOM_SEND_RANGE) + 1
end

def run_detect_thread
  # 速度偵測
  $thr_detect.exit if $thr_detect
  $thr_detect = Thread.new do
    loop do
      $speed_report = $interval_send
      printf("總共傳輸：%.6f Mbit，當前速度：%.3f Mbit/s\n",$total_send*8.0/UNIT_MEGA,$interval_send * 8.0 /UNIT_MEGA )
      $interval_send = 0
      sleep 1
    end
  end
end
def run_monitor_thread
  $thr_monitor.exit if $thr_monitor
  # 連接監測器
  $thr_monitor = Thread.new do
    while line = $controller_sock.gets
      case line
      when /spd/
        if $running
          
          cmd = "#{($speed_report * 8.0).ceil }"
          if $assign_report
            $assign_report = false
            cmd += ' assigned'
          end
          $controller_sock.puts cmd
        else
          $controller_sock.puts 'close'
          break
        end
      when /add/
        data = line.split
        eval "$speed = $speed #{data[1]}"
      when /mul/
        data = line.split
        eval "$speed = ($speed * #{data[1]}).round"
      when /assign/
        spd = line.split[1].to_i
        $assign_report = true
        $speed = spd * SEND_INTERVAL
      end
    end
  end
end

def restart_client
  # stop and notification
  $running = false
  
  # stop threads
  $thr_detect.exit if $thr_detect
  $thr_monitor.join if $thr_monitor

  # close servers 
  $controller_sock.close


  # sleep for a while
  sleep rand(CLIENT_RANDOM_SLEEP_RANGE)+1

  # connect to controller
  connect_controller
  # reset variables
  clear_variables

  # reset time
  reset_time

  # restart threads
  run_detect_thread
  run_monitor_thread
end

# ---- main ----
if CLIENT_RANDOM_START > 0
  sleep rand(CLIENT_RANDOM_START)
end
if CLIENT_RANDOM_FIXED_SEED
  srand($port)
end

connect_server
connect_controller
clear_variables
reset_time
run_detect_thread
run_monitor_thread

begin
  cnt = 0
  loop do
    $delay_send += $speed
    if $delay_send >= PACKET_SIZE
      pkts = $delay_send / PACKET_SIZE
      $delay_send %= PACKET_SIZE
      for i in 0...pkts
        info = "#{cnt} "
        data =  info + "0" * (PACKET_SIZE - info.size)
        send = $sender.send(data,0)
        $total_send += send
        $interval_send += send
        cnt += 1
      end
    end
    if CLIENT_RANDOM_ENABLED && Time.now > $next_stop_time
      restart_client
    end
    sleep SEND_INTERVAL
  end
rescue SystemExit, Interrupt 
  $running = false
  $thr_monitor.exit if $thr_monitor
  $thr_detect.exit if $thr_detect
  $controller_sock.puts "close" if !$controller_sock.closed? 
  puts "終止傳輸，再按一次Ctrl+C結束程式"
  printf("總共傳輸：%.6f Mbit\n",($total_send*8.0)/UNIT_MEGA )
end
loop do
  sleep 1
end
