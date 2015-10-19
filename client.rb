#!/usr/bin/env ruby 

require 'socket'
require 'thread'
require 'fileutils'
require_relative 'host-info'
require_relative 'qos-info'

$DEBUG = true

SEND_INTERVAL = 0.001
if ENABLE_CONTROL
  if ENABLE_ASSIGN
    INIT_SPEED_PER_SECOND = 0
  else
    INIT_SPEED_PER_SECOND = 8*1000
  end
else
  INIT_SPEED_PER_SECOND = 2 * MAX_SPEED / 8
end
INIT_SPEED_PER_INTERVAL = INIT_SPEED_PER_SECOND * SEND_INTERVAL





$host = ARGV[0]
$port = ARGV[1].to_i
$size_remain_mutex = Mutex.new
$pattern_size_ready = ConditionVariable.new
$log_name=sprintf(HOST_LOG_NAME_FORMAT,$port)

FileUtils.rm_f $log_name


def connect_server
  case DATA_PROTOCOL
  when :tcp
    $sender = TCPSocket.new($host,$port)
  when :udp
    $sender = UDPSocket.new
    $sender.connect($host,$port)

  end
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
  $this_time_send = 0
end

def reset_size_remaining
  $size_remaining = rand(CLIENT_RANDOM_SEND_SIZE_RANGE) + 1
end

def reset_time
  $next_stop_time = Time.now + rand(CLIENT_RANDOM_SEND_TIME_RANGE) + 1
end

def reset_random
  case CLIENT_RANDOM_MODE
  when :time
    reset_time
  when :size
    reset_size_remaining
  end
end

def run_detect_thread
  # 速度偵測
  $thr_detect.exit if $thr_detect
  $thr_detect = Thread.new do
    loop do
      $speed_report = $interval_send
      # 紀錄檔案
      if $start_logging
        File.open($log_name,'a') do |f|
          f.puts $interval_send
        end
      end
      if $running
        # 顯示文字
        remain_str = ''
        case CLIENT_RANDOM_MODE
        when :size,:pattern
          remain_str = sprintf("還需傳輸%.6f MB(%d bytes)，",$size_remaining/UNIT_MEGA.to_f,$size_remaining)
        end
        printf("總共傳輸：%.6f MB，%s當前速度：%.3f Mbit/s\n",$total_send.to_f/UNIT_MEGA,remain_str,$interval_send * 8.0 /UNIT_MEGA )
      end
      $interval_send = 0
      sleep 1
    end
  end
end
def run_monitor_thread
  $thr_monitor.exit if $thr_monitor
  # 連接監測器
  if ENABLE_CONTROL
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
        when /interval_add/
          data = line.split
          puts "重新分配加速：#{sprintf("%+d",data[1].to_i*SEND_INTERVAL)}"
          eval "$speed = $speed #{sprintf("%+d",data[1].to_i*SEND_INTERVAL)}"
        when /add/
          data = line.split
          eval "$speed = $speed #{data[1]}"
        when /mul/
          data = line.split
          eval "$speed = ($speed * #{data[1]}).round"
        when /assign/
          spd = line.split[1].to_i
          #puts "速度被指派為#{spd*8.0 / UNIT_MEGA} Mbits"
          $assign_report = true
          $speed = spd * SEND_INTERVAL
        end
      end
    end
  end
end

def run_pattern_thread
  $thr_pattern.exit if $thr_pattern
  if CLIENT_RANDOM_MODE == :pattern
    $thr_pattern = Thread.new do
      new_added = 0
      File.open(sprintf(CLIENT_PATTERN_NAME_FORMAT,$port)) do |f|
        while line = f.gets
          puts "讀取pattern：#{line}"
          if line =~ /^[ \t]*#/ # comments
            next
          elsif line =~ /sleep (.*)/
            if new_added > 0
              printf("新增傳輸需求：%.6f MB(%d bytes)\n",new_added.to_f/UNIT_MEGA,new_added)
              $size_remain_mutex.synchronize do
                $size_remaining += new_added
                $pattern_size_ready.signal
              end
              new_added = 0

            end
            sleep_time = $1.to_f
            sleep sleep_time
          else
            new_added += line.to_i
          end
        end
      end
      if new_added > 0
        printf("新增傳輸需求：%.6f MB(%d bytes)\n",new_added.to_f/UNIT_MEGA,new_added)
        $size_remain_mutex.synchronize do
          $size_remaining += new_added
          $pattern_size_ready.signal
        end
        new_added = 0
      end

      puts "pattern結束，sleep forever"
      $start_logging = false
      loop do
        sleep
      end
    end
  end
end

def check_restart?
  case CLIENT_RANDOM_MODE
  when :time
    return Time.now > $next_stop_time
  when :size,:pattern
    return $size_remaining <= 0  
  end


end


def wait_for_next
  case CLIENT_RANDOM_MODE
  when :time,:size
    sleep rand(CLIENT_RANDOM_SLEEP_RANGE)+1
  when :pattern
    $size_remain_mutex.synchronize do
      if $size_remaining <= 0
        puts "等待傳輸需求..."
        $pattern_size_ready.wait($size_remain_mutex)
      end
    end
    puts "已取得傳輸要求！"
  end
end

def restart_client
  # stop and notification
  $running = false

  # stop threads
  $thr_monitor.join if $thr_monitor

  # close servers 
  $controller_sock.close

  # 顯示資訊
  puts "本次傳輸共#{sprintf("%.6f",$this_time_send/UNIT_MEGA.to_f)} MB(#{$this_time_send} bytes)"

  # wait for next transmit
  wait_for_next

  # connect to controller
  connect_controller
  # reset variables
  clear_variables

  # reset random
  reset_random

  # restart threads
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
$stop_count_time = false
$trans_time = 0.0
$trans_size = 0.0
$start_logging = true
case CLIENT_RANDOM_MODE
when :time
  reset_time
when :size
  reset_size_remaining
when :pattern
  $size_remaining = 0
end
run_detect_thread
run_monitor_thread
run_pattern_thread

begin
  cnt = 0
  $start_time = Time.now
  loop do
    $delay_send += $speed
    if $delay_send >= PACKET_SIZE
      pkts = $delay_send / PACKET_SIZE
      $delay_send %= PACKET_SIZE
      for i in 0...pkts
        info = "#{cnt} "
        data =  info + "1" * (PACKET_SIZE - info.size)
        send = $sender.send(data,0)
        $total_send += send
        $interval_send += send
        $this_time_send += send
        $trans_size += send
        cnt += 1
        # 檢查離開
        if CLIENT_RANDOM_MODE == :size || CLIENT_RANDOM_MODE == :pattern
          $size_remain_mutex.synchronize do
            $size_remaining -= send
            if $size_remaining <= 0
              $size_remaining = 0
              break
            end
          end
        end
      end
    end
    if CLIENT_STOP_SIZE_BYTE > 0 && CLIENT_RANDOM_MODE != :pattern && $trans_size >= CLIENT_STOP_SIZE_BYTE
      raise SystemExit
    end
    if CLIENT_RANDOM_MODE && check_restart?
      $stop_time = Time.now
      $trans_time += ( $stop_time - $start_time) if !$stop_count_time
      $start_time = $stop_time
      restart_client
      $start_time = Time.now
    end
    sleep SEND_INTERVAL
  end
rescue SystemExit, Interrupt
  $stop_time = Time.now if !$stop_time
  $trans_time += ($stop_time - $start_time) if !$stop_count_time
  $sender.send("reset #{'0'*(PACKET_SIZE - 6)}",0)
  $running = false
  $thr_monitor.exit if $thr_monitor
  $thr_detect.exit if $thr_detect
  $thr_pattern.exit if $thr_pattern
  $controller_sock.puts "close" if !$controller_sock.closed? 
  puts "終止傳輸，再按一次Ctrl+C結束程式"
  printf("總共傳輸：%.6f Mbit，花費在傳輸上的時間：%.6f 秒，平均速度：%.6f Mbits\n",($trans_size*8.0)/UNIT_MEGA, $trans_time, ($trans_size*8.0)/($trans_time*UNIT_MEGA) )
end
sleep
