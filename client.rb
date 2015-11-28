#!/usr/bin/env ruby 

require 'socket'
require 'thread'
require 'fileutils'
require_relative 'host-info'
require_relative 'qos-info'
require_relative 'qos-lib'

$DEBUG = true

if ENABLE_CONTROL
  if ENABLE_ASSIGN
    INIT_SPEED_PER_SECOND = 8*CTRL_ASSIGN_BASELINE 
  else
    INIT_SPEED_PER_SECOND = 8*1000
  end
else
  INIT_SPEED_PER_SECOND = 2 * MAX_SPEED / 8
end
INIT_SPEED_PER_INTERVAL = INIT_SPEED_PER_SECOND * CLI_SEND_INTERVAL





$host = ARGV[0]
$port = ARGV[1].to_i
$size_remain_mutex = Mutex.new
$pattern_size_ready = ConditionVariable.new
$request_finish = ConditionVariable.new
$log_name=sprintf(HOST_LOG_NAME_FORMAT,$port)

FileUtils.rm_f $log_name


def connect_server
  case DATA_PROTOCOL
  when :tcp
    $sender = TCPSocket.new($host,$port)
  when :udp
    $sender = UDPSocket.new
    $sender.bind("0.0.0.0",$port)
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
  $sub_count = 0
  $accept_rate = 1.0
  $ack_send = 0
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

def send_recv_pkt_request(pkts)
  req = {}
  req[:is_request] = true
  req[:type] = "recv_pkt_request"
  req[:data_size] = pkts
  return $sender.send(pack_command(req),0)


end

def send_recv_request(size)
  req = {}
  req[:is_request] = true
  req[:type] = "recv_request"
  req[:data_size] = size
  return $sender.send(pack_command(req),0)
end

def wait_for_recv_request(size)
  puts "等待recv #{size} 的recv confirm..."
  send_recv_request(size)
  # 等待對方傳回確認訊息，若沒有則每隔固定時間重送要求
  loop do
    ready = IO.select([$sender],[],[],1)
    rs = ready ? ready[0] : nil
    if rs && r = rs[0]
      # can receive message, check if it's a confirm
      str = $sender.read(PACKET_SIZE)
      if check_is_recv_request_confirm?(size,str)
        # it an ack, break loop
        break
      else
        # Not a ack
        puts "收到非#{size}的recv request confirm忽略"
      end
    else
      # Timedout
      puts "等待recv #{size}的confirm逾時逾時"
    end
    # 重送：超過時間或收到的不是確認訊息
    send_recv_request(size)
  end
  puts "已收到recv confirm"
  
end

def wait_recv_pkt_ack
  # Replay ack req
  str = $sender.read(PACKET_SIZE)
  req = parse_command(str)
  req[:is_request] = false
  req[:is_reply] = true
  $sender.send(pack_command(req),0)
end

def read_data_from_server(size)
  start = Time.now
  $start_read = true
  # send req & wait for confirm
  wait_for_recv_request(size)
  # loop do: recv and wait 
  total_pkts = 0
  puts "開始接收資料：#{size}"
  while size > 0
    send_size = [size,CLI_ACK_SLICE].min
    size -= send_size
    # compute pkts
    pkts = (send_size.to_f / PACKET_SIZE).ceil
    total_pkts += pkts
    # send request for pkts
    send_recv_pkt_request(pkts)
    # recv pkts
    expired = false
    recvs = {}
    ok = 0
    pkts.times do |i|
      ready = IO.select([$sender],[],[],1)
      rs = ready ? ready[0] : nil
      if rs && r = rs[0]
        ok += 1
        str = $sender.read(PACKET_SIZE)
        req = parse_command(str)
        if req[:type] == "recv_pkt_ack" 
          puts "收到預期外的ACK"
          # Replay ack req
          req[:is_request] = false
          req[:is_reply] = true
          $sender.send(pack_command(req),0)
        else
          if recvs.has_key? req[:task_no]
            puts "重複編號：#{req[:task_no]}"
          else
            recvs[req[:task_no]] = req

          end
        end
      else
        puts "recv pkts逾時！重新傳送此單位"
        expired = true
        break
      end
    end
    puts "在#{pkts}次中成功#{ok}次" if ok != pkts
    if expired || recvs.keys.size != pkts
      puts "recv pkts封包數量錯誤！預期：#{pkts}個，收到：#{recvs.keys.size}個，或者發生逾時！"
      list = (0..pkts).to_a
      puts "遺失清單：#{(list - recvs.keys).join(',')}"
      # restart
      size += send_size
      next
    end
    # then server will wait for ack, send it back!
    puts "剩餘大小：#{size}"
    wait_recv_pkt_ack
    #spin_time (rand(11)+5)*0.0001
    spin_time 0.1
  end
  puts "已收到來自server的#{total_pkts}個封包，花費時間：#{Time.now - start}秒"
  # cleanup 
  $start_read = false
end

def run_detect_thread
  # 速度偵測
  $thr_detect.exit if $thr_detect
  $thr_detect = Thread.new do
    last_time = Time.now
    loop do
      # Timing compute
      this_time = Time.now
      if this_time - last_time < 1.0
        sleep 0.01
        next
      end
      last_time = Time.now

      $speed_report = $interval_send
      #$speed_report = $speed / CLI_SEND_INTERVAL.to_f
      # 紀錄檔案
      if $start_logging
        File.open($log_name,'a') do |f|
          f.puts "#{Time.now.to_f} #{$speed_report}"
        end
      end
      if $running && !$start_read
        # 顯示文字
        remain_str = ''
        case CLIENT_RANDOM_MODE
        when :size,:pattern
          remain_str = sprintf("還需傳輸%.6f MB(%d bytes)，",$size_remaining/UNIT_MEGA.to_f,$size_remaining)
        end
        printf("總共傳輸：%.6f MB，%s當前速度：%.3f Mbps\n",$total_send.to_f/UNIT_MEGA,remain_str,$speed_report * 8.0 /UNIT_MEGA )
      end
      $interval_send = 0
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
          puts "重新分配加速：#{sprintf("%+d",data[1].to_i*CLI_SEND_INTERVAL)}" if !$start_read
          eval "$speed = $speed #{sprintf("%+d",data[1].to_i*CLI_SEND_INTERVAL)}"
        when /add/
          data = line.split
          eval "$speed = $speed #{data[1]}"
        when /mul/
          puts "在#{Time.now.to_f}收到！" if DEBUG_TIMING
          data = line.split
          eval "$speed = ($speed * #{data[1]}).round"
        when /assign/
          spd = line.split[1].to_i
          puts "速度被指派為#{spd*8.0 / UNIT_MEGA} Mbits" if !$start_read
          $assign_report = true
          $speed = spd * CLI_SEND_INTERVAL
        when /acc_rate (.*)/
          $accept_rate = $1.to_f
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
            # read 100MB
            read_data_from_server(5*UNIT_MEGA)

            if new_added > 0
              printf("新增傳輸需求：%.6f MB(%d bytes)\n",new_added.to_f/UNIT_MEGA,new_added)
              $size_remain_mutex.synchronize do
                $size_remaining += new_added
                $pattern_size_ready.signal
              end
              new_added = 0
              # 等待sender傳送結束
              $size_remain_mutex.synchronize do
                $request_finish.wait($size_remain_mutex)
              end
              puts "本次需求傳輸結束！等待下次需求..."

            end
            sleep_time = $1.to_f
            sleep sleep_time
          else
            new_added += line.to_i
          end
        end
      end
      # read 100MB
      read_data_from_server(1*UNIT_MEGA)
      if new_added > 0
        # 新增傳輸需求給sender
        printf("新增傳輸需求：%.6f MB(%d bytes)\n",new_added.to_f/UNIT_MEGA,new_added)
        $size_remain_mutex.synchronize do
          $size_remaining += new_added
          $pattern_size_ready.signal
        end
        new_added = 0
        # 等待sender傳送結束
        $size_remain_mutex.synchronize do
          $request_finish.wait($size_remain_mutex)
        end

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
    puts "任務編號:#{$task_no}已結束，等待下一個傳輸需求..."
    $size_remain_mutex.synchronize do
      $request_finish.signal
      if $size_remaining <= 0
        $pattern_size_ready.wait($size_remain_mutex)
      end
    end
    $task_no += 1
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
  
  puts "開始傳輸任務編號：#{$task_no}，等待確認中..."
  wait_for_confirm_task
end

def generate_request_str
  req = {}
  req[:is_request] = true
  req[:type] = "send_request"
  req[:task_no] = $task_no
  req[:sub_no] = [0]
  req[:data_size] = $size_remaining
  pack_command(req)
end


def send_reset
  req = {}
  req[:type] = "reset"
  $sender.send(pack_command(req),0)
end

def send_data(cnt)
  req = {}
  req[:is_request] = true
  req[:type] = "send"
  req[:task_no] = $task_no
  req[:sub_no] = [cnt]
  req[:data_size] = $size_remaining
  return $sender.send(pack_command(req),0)
end

def send_request_for_send
  puts "開始傳送#{$task_no}的send request"
  str = generate_request_str
  $sender.send(str,0)
end

def check_is_confirm?(task_no,str)
  req = parse_command(str)
  # confirm格式：reply + send_confirm + task_no + sub = [0]
  return req[:is_reply] && req[:type] == "send_confirm" && req[:task_no] == task_no && req[:sub_no] == [0]
end

def check_is_send_ack?(task_no,str)
  req = parse_command(str)
  # confirm格式：reply + send_confirm + task_no + sub = [0]
  return req[:is_reply] && req[:type] == "send_ack" && req[:task_no] == task_no && req[:sub_no] == [0]
end

def check_is_recv_request_confirm?(size,str)
  req = parse_command(str)
  # confirm格式：reply + recv_confirm
  return req[:is_reply] && req[:type] == "recv_confirm"  && req[:data_size] == size
end
def wait_for_confirm_task
  # 傳送要求
  send_request_for_send
  # 等待對方傳回確認訊息，若沒有則每隔固定時間重送要求
  loop do
    puts "傳輸成功率：#{$accept_rate}"
    if $accept_rate < rand
      puts "被controller要求延遲傳送request..."
      sleep 1
      next
    else
      puts "允許傳送request！"
    end
    ready = IO.select([$sender],[],[],1)
    rs = ready ? ready[0] : nil
    if rs && r = rs[0]
      # can receive message, check if it's a confirm
      str = $sender.read(PACKET_SIZE)
      if check_is_confirm?($task_no,str)
        # it a confirm, break loop
        break
      else
        # Not a confirm
        puts "收到非#{$task_no}的確認訊息，忽略"
      end
    else
      # Timedout
      puts "等待#{$task_no}的確認逾時逾時"
    end
    # 重送：超過時間或收到的不是確認訊息
    send_request_for_send
    $re_send_count += 1
  end
  puts "已收到#{$task_no}的確認訊息，開始傳輸！"
end

def send_ack_request
  req = {}
  req[:is_request] = true
  req[:type] = "send_ack"
  req[:task_no] = $task_no
  str = pack_command(req)
  $sender.send(str,0)
end

def wait_for_ack
  if !CLI_WAIT_FOR_ACK
    return
  end
  send_ack_request
  # 等待對方傳回確認訊息，若沒有則每隔固定時間重送要求
  loop do
    ready = IO.select([$sender],[],[],1)
    rs = ready ? ready[0] : nil
    if rs && r = rs[0]
      # can receive message, check if it's a confirm
      str = $sender.read(PACKET_SIZE)
      if check_is_send_ack?($task_no,str)
        # it an ack, break loop
        break
      else
        # Not a ack
        puts "收到非#{$task_no}的ACK訊息，忽略"
      end
    else
      # Timedout
      puts "等待#{$task_no}的ACK逾時逾時"
    end
    # 重送：超過時間或收到的不是確認訊息
    send_ack_request
  end
  #puts "已收到#{$task_no}的ACK訊息，繼續傳輸！"
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
$task_no = 0
$re_send_count = 0 # 總計重送封包之次數
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
$size_remain_mutex.synchronize do
  if $size_remaining <= 0
    puts "等待最初傳輸需求..."
    $pattern_size_ready.wait($size_remain_mutex)
  end
end


begin
  $sub_count = 1
  $start_time = Time.now
  puts "開始傳輸任務編號：#{$task_no}，等待確認中..."
  wait_for_confirm_task
  last_time = Time.now
  loop do
    # Timing compute
    this_time = Time.now
    if this_time - last_time < CLI_SEND_INTERVAL
      sleep CLI_SEND_DETECT_INTERVAL
      next
    end
    last_time = Time.now
    $delay_send += $speed
    if $delay_send >= PACKET_SIZE
      pkts = $delay_send.to_i / PACKET_SIZE
      $delay_send -= pkts * PACKET_SIZE
      for i in 0...pkts
        # Send a packet here
        send = send_data($sub_count)
        $total_send += send
        $interval_send += send
        $this_time_send += send
        $trans_size += send
        $sub_count += 1
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
        $ack_send += send
        # 等待ACK
        if $ack_send >= CLI_ACK_SLICE
          #puts "等待ACK中..."
          $ack_send = 0
          wait_for_ack
        end
      end # end for
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
  end
rescue SystemExit, Interrupt
  $stop_time = Time.now if !$stop_time
  $trans_time += ($stop_time - $start_time) if !$stop_count_time
  send_reset
  $running = false
  $thr_monitor.exit if $thr_monitor
  $thr_detect.exit if $thr_detect
  $thr_pattern.exit if $thr_pattern
  $controller_sock.puts "close" if !$controller_sock.closed? 
  puts "終止傳輸，再按一次Ctrl+C結束程式"
  printf("總共傳輸：%.6f Mbit，花費在傳輸上的時間：%.6f 秒，平均速度：%.6f Mbits\n",($trans_size*8.0)/UNIT_MEGA, $trans_time, ($trans_size*8.0)/($trans_time*UNIT_MEGA) )
end
sleep
