#!/usr/bin/env ruby 

require 'socket'
require 'thread'
require './qos-info.rb'
require './host-info.rb'

$DEBUG = true

SHOW_INTERVAL = 0.1
UPSTREAM_INFO.default = []


# 自動產生host歸屬表
$host_belong_sw = {}
$port_data = {}
UPSTREAM_INFO.each_pair do |port,list|
  data = {port: port,connect: false,avg_speed: 0.0,host_count: 0,div_spd: MAX_SPEED_M,should_spd: MAX_SPEED_M,last_should_spd: MAX_SPEED_M,new_should_spd: MAX_SPEED_M,total_spd: 0,util_total: 0,util_cnt:0}
  list.each do |host|
    $host_belong_sw[host] = [] if !$host_belong_sw.has_key? host
    $host_belong_sw[host] << data
  end
  $port_data[port] = data
end


$client_sw = {}
$client_host = {}



$conn_mutex = Mutex.new

# 檢測client到來的thread
thr_accept = Thread.new do
  serv = TCPServer.new CONTROLLER_PORT
  loop do
    c = serv.accept
    type,id = c.gets.split
    case type
    when /switch/
      data = {fd:c, len: 0,last_len: 0,spd: 0,last_spd: 0, last_mod: Time.at(0)}
      $conn_mutex.synchronize do
        $client_sw[id] = data
      end
      $port_data[id][:connect] = true
    when /host/
      data = {fd:c, spd: 0, cmd: '',expect_spd: 0, show_cmd: ''}
      addr = c.peeraddr(false)
      id = addr[3]
      $conn_mutex.synchronize do 
        $client_host[id] = data
      end
      $host_belong_sw[id].each do |data|
        data[:host_count] += 1
      end
    else
      puts "無法辨別的client"
      c.close
    end
  end
end

def host_cmd_generate(cmd,val)
  sprintf("%3s %4s",cmd,val)
end

def reset_host_command
  $client_host.values.each do |data|
    data[:cmd] = ''
    data[:expect_spd] = MAX_SPEED 
  end
end

def write_host_command
  $client_host.clone.each_pair do |id,data|
    if !data[:cmd].empty?
      #puts "#{id} 寫入：#{data[:cmd]}"
      data[:fd].puts data[:cmd]
      data[:show_cmd] = data[:cmd]
    end
  end
end
# 速度調整檢查(對上游switch之調整) 
def upstream_switch_speed_adjuct(src_port,src_data) 
  src_port_data = $port_data[src_port]
  # 每個上游switch蒐集自己的host，累積其div_speed得到該switch outport最後的速度
  sw = UPSTREAM_SWITCH[src_port] || []
  sw.each do |up_sw|
    final_spd = 0
    UPSTREAM_INFO[up_sw].each do |host|
      sw_for_host = $host_belong_sw[host]
      # 找出那些在瓶頸switch中佔有之div_spd量，並加總
      # 當前得先檢查是不是連線了 
      sw_for_host.each do |data|
        if data[:port] == src_port && $client_host.has_key?(host)
          final_spd += src_port_data[:div_spd]
        end
      end
    end
    #puts "#{up_sw}速度應調整為：#{final_spd}Mbits"
    # 取最小者當作最後應調整的速度
    port_data = $port_data[up_sw]
    if final_spd > 0 && final_spd < port_data[:new_should_spd]
      port_data[:new_should_spd] = final_spd
    end
  end
end

def reset_should_speed
  $port_data.values.each do |data|
    data[:new_should_spd] = MAX_SPEED_M
  end
end

def write_should_speed
  $port_data.each_pair do |port,data|
    # 要檢查該switch是否連線
    if data[:connect] && data[:new_should_spd] != data[:last_should_spd] 
      writing = data[:should_spd] = data[:new_should_spd]
      fd = $client_sw[port][:fd]
      avg = (data[:avg_speed] / 1000000.0).floor
      if writing < avg
        writing = avg
      end
      fd.puts "assign #{writing}"
      data[:last_should_spd] = writing
    end
  end
end

def process_switches
  reset_should_speed
  reset_host_command
  now = Time.now
  switches = []
  $client_sw.clone.each_pair do |id,data|
    switches[STARTING_ORDER.index(id)] = [id,data]
  end
  switches.each_with_index do |obj,index|
    id,data = obj
    fd = data[:fd]

    # 讀取：速度與queue長度
    cmd = fd.gets
    case cmd
    when /close/
      fd.close
      #puts "Switch Monitor #{id} 中斷連線！"
      $conn_mutex.synchronize do
        $client_sw.delete id
      end
      $port_data[id][:connect] = false
    when /len=(\d+),spd=(\d+)/
      # 更新Len
      data[:last_len] = data[:len]
      data[:len] = $1.to_i
      # 更新spd 
      data[:last_spd] = data[:spd]
      data[:spd] = $2.to_i

    else
      # 無法識別
    end

    # 速度調整檢查(對上游switch之調整) 
    upstream_switch_speed_adjuct(id,data) 
    #puts $port_data

    # 通知最短時間，queue越長，就可以快速通知避免爆炸
    threshold = 0.1
    len = data[:len]
    if len > 500
      threshold = 0.05
    elsif len > 600
      threshold = 0.01
    elsif len > 700
      threshold = 0.001
    elsif len > 900
      threshold = 0
    end

    if now - data[:last_mod] > threshold
      data[:last_mod] = now
      check_switch_queue(id,data)
    end
  end
  write_host_command
  write_should_speed
end

def check_switch_queue(id,data)
  len = data[:len]
  diff = len - data[:last_len]
  add = nil
  mul = nil

  # 快速增加的條件：低於div_spd的80%
  if len <= 1 
    add = 100
  elsif len <= 5
    add = 10
  elsif len <= 25
    add = 5
  elsif len <= 50
    add = 1
  elsif len > 50 && len <= 100
    add = 0
  elsif len > 100 && len <= 150
    add = -1
  elsif len > 150 && len < 200
    if diff < 0 # 下降
      low = 3
    else
      low = ((len - 150.0)/10.0).round + 2
    end
    add  = low * -10
  elsif len >= 300
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.9
    end
  elsif len >= 400
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.7
    end
  elsif len >= 500
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.5
    end
  elsif len >= 600
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.3
    end
  elsif len >= 700
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.2
    end
  elsif len >= 800
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.1
    end
  elsif len >= 900
    if diff < 0 # 下降
      mul = nil
    else
      mul = 0.0
    end
  end
  UPSTREAM_INFO[id].each do |host_id|
    host_data = $client_host[host_id]
    if host_data
      cmd = ''
      if host_data[:spd] == 0
        # 初始速度
        min_data = $host_belong_sw[host_id].min do |a,b|
          (a[:should_spd]*1000000 - a[:total_spd]) <=> (b[:should_spd]*1000000 - b[:total_spd])
        end
        max_spd = (min_data[:should_spd]*1000000 - min_data[:total_spd])/8
        if max_spd > 0
          min_div = min_data[:div_spd] * (1000000/8) 
          if max_spd > min_div
            max_spd = min_div
          end
          current = (max_spd * 0.8).round
          cmd = "assign #{current}"
          host_data[:expect_spd] = current
          host_data[:cmd] = cmd
        end
      elsif mul
        current = host_data[:spd] * mul
        if current < host_data[:expect_spd]
          cmd = host_cmd_generate("mul",mul)
          host_data[:expect_spd] = current
          host_data[:cmd] = cmd
        end
      elsif add
        # 平均速度檢查
        final_add = add
        curr_spd = host_data[:spd]
        if $host_belong_sw[host_id].any? {|data| (curr_spd - data[:avg_speed]) > data[:avg_speed] * 0.05}
          final_add -= 100
        end
        # 檢查接近滿速 
        if host_data[:spd] > ($host_belong_sw[host_id][0][:div_spd] * 1000000  * 0.9)
          final_add = 10 if final_add > 10 
        end

        #puts "來自#{id}的指令：#{final_add}"
        current = host_data[:spd] + final_add
        if current < host_data[:expect_spd]
          cmd = host_cmd_generate("add",sprintf("%+d",final_add))
          host_data[:expect_spd] = current
          host_data[:cmd] = cmd
        end
      end
      # 指令覆蓋，取預測結果最低者
      #fd = host_data[:fd]
      #fd.puts cmd if !cmd.empty?
      #puts "最終#{host_id}期望指令：#{host_data[:cmd]}"
    end
  end
end

def process_hosts
  port_data = {}
  $client_host.clone.each_pair do |id,data|
    fd = data[:fd]
    # 取得速度
    fd.puts "spd"
    cmd = fd.gets
    case cmd
    when /close/
      fd.close
      $conn_mutex.synchronize do
        $client_host.delete id
      end
      $host_belong_sw[id].each do |data|
        data[:host_count] -= 1
      end
    when /\d+/
      # 更新spd
      spd = data[:spd] = cmd.to_i
      $host_belong_sw[id].each do |data|
        port = data[:port]
        port_data[port] = [0.0,0] if !port_data.has_key? port
        port_data[port][0] += spd
        port_data[port][1] += 1
      end
    else
      # 無法識別
    end
  end
  port_data.each_pair do |port,data|
    if data[1] == 0
      avg_spd = 0.0
      div_spd = $port_data[port][:should_spd]
    else
      avg_spd = data[0] / data[1].to_f
      div_spd = ($port_data[port][:should_spd] / data[1]).floor
    end
    $port_data[port][:avg_speed] = avg_spd
    $port_data[port][:div_spd] = div_spd
    $port_data[port][:total_spd] = data[0]
  end
  $port_data.each_pair do |port,data|
    if data[:host_count] <= 0
      data[:avg_speed] = 0.0
    end
  end
end
def show_info
  #puts `clear`
  puts "===各switch port queue狀況與該port平均速度==="
  $client_sw.clone.each_pair do |id,data|
    len = data[:len] 
    bar_len = (len / 25.0).ceil
    p_data = $port_data[id]
    current_util = ($port_data[id][:total_spd]/((data[:spd] > 0 ? data[:spd] : MAX_SPEED_M)*1000000.0)*100).floor
    if current_util <= 0
      total_util = 0
    else
      p_data[:util_total] += current_util
      p_data[:util_cnt] += 1
      total_util = p_data[:util_total] / p_data[:util_cnt] 
    end
    printf("%8s,限：%3d M, 均：%8.3f M,商：%3d M,應：%3d M,CU: %3d %%,TU: %3d %%, %5d ,%s\n",id,data[:spd],$port_data[id][:avg_speed] / 1000000.0,$port_data[id][:div_spd],$port_data[id][:should_spd],current_util,total_util,len,"|"*bar_len)
  end
  puts "===各host speed狀況==="
  $client_host.each_pair do |id,data|
    speed = data[:spd] / 1000000.0
    bar_len = speed.round / 2
    printf("%8s, %8.3f Mbits,速度變化：%9s,%s\n",id,speed,data[:show_cmd],"|"*bar_len)
  end
end

# 通知client
def notify_client(client,len)
  diff = len - $last_len
  $last_len = len
  cmd = ''
  state = ''
  client.puts cmd if !cmd.empty?
  if !state.empty?
    bar_len = len / 10
    printf("%5d, %s, 速度變化：%5s, Queue:%s\n",len,state,cmd,"|"*bar_len);
  end
end
# 處理switch monitor 
thr_switch = Thread.new do
  loop do
    process_switches
  end
end
# 處理host 
thr_host = Thread.new do
  loop do
    process_hosts
  end
end
# 顯示資訊 
thr_show = Thread.new do
  loop do
    show_info
    sleep SHOW_INTERVAL
  end
end
# Main
begin
  loop do
    sleep 10
  end
rescue SystemExit, Interrupt
  thr_accept.exit
  thr_switch.exit
  thr_host.exit
  thr_show.exit
  ($client_sw.values + $client_host.values).each do |data|
    c = data[:fd]
    c.close if !c.closed?
  end
end
