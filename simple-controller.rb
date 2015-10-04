#!/usr/bin/env ruby 

require 'socket'
require 'thread'
require_relative 'qos-info'
require_relative 'host-info'

$DEBUG = true

SHOW_INTERVAL = 0.1
UPSTREAM_INFO.default = []


# 自動產生host歸屬表
$host_belong_sw = {}
$port_data = {}
UPSTREAM_INFO.each_pair do |port,list|
  data = {port: port,connect: false,avg_speed: 0.0,host_count: 0,div_spd: MAX_SPEED_M,should_spd: MAX_SPEED_M,last_should_spd: MAX_SPEED_M,new_should_spd: MAX_SPEED_M,total_spd: 0,util_total: 0,util_cnt:0,recent_util: []}
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
      data = {fd:c, spd: 0, cmd: '',expect_spd: 0, show_cmd: '', speed_assigned: 0, assign_locked: false}
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
      avg = (data[:avg_speed] / UNIT_MEGA.to_f).floor
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
    threshold = MAX_NOTIFICATION_INTERVAL
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
  if len < 1 
    add = 100
  elsif len <= 5
    add = 20
  elsif len <= 25
    add = 10
  elsif len <= 50
    add = 5
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
      if ENABLE_ASSIGN && host_data[:spd] == 0 && len < 200
        # 初始速度
        min_data = $host_belong_sw[host_id].min do |a,b|
          (a[:should_spd]*UNIT_MEGA - a[:total_spd]) <=> (b[:should_spd]*UNIT_MEGA - b[:total_spd])
        end
        max_spd = (min_data[:should_spd]*UNIT_MEGA - min_data[:total_spd])/8
        if max_spd > 0
          # 檢查最大速度
          min_div = min_data[:div_spd] * (UNIT_MEGA/8) 
          if max_spd > min_div
            max_spd = min_div
          end
          # 檢查該host所屬之所有switch中，最大允許的流量
          sw_allow = check_max_host_upstream_switch_allow(host_id)
          if max_spd > sw_allow
            max_spd = sw_allow
          end
          # 根據當前host數量降低assign強度
          host_count = $port_data[id][:host_count]
          if host_count > 1
            div_rate = Math.log(host_count,1.7)
            max_spd = max_spd / div_rate
          end

          # 給予比率
          current = (max_spd * ASSIGN_RATE).round
          cmd = "assign #{current}"
          host_data[:expect_spd] = current
          host_data[:cmd] = cmd
          host_data[:speed_assigned] = current * 8
          host_data[:assign_locked] = true
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
        if $host_belong_sw[host_id].any? {|data| (curr_spd - data[:avg_speed]) > data[:avg_speed] * 0.05 &&
                                          (curr_spd > data[:div_spd]*UNIT_MEGA )}
          final_add -= 100
        end
        # 檢查接近滿速 
        if host_data[:spd] > ($host_belong_sw[host_id][0][:div_spd] * UNIT_MEGA  * 0.9)
          final_add = 10 if final_add > 10
        end
        # 加法均分 
        final_add = ( final_add / $port_data[id][:host_count]).round

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
    fd.puts "spd" if !fd.closed?
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
    when /(\d+)(.*)/i
      # 更新spd
      spd = data[:spd] = $1.to_i
      # 檢查解鎖
      if $2 =~ /assigned/i
        data[:assign_locked] = false
      end
      if !data[:assign_locked]
        data[:speed_assigned] = spd
      end
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

def check_max_host_upstream_switch_allow(host_id)
  max_allow = MAX_SPEED * MAX_BW_UTIL_RATE
  # 檢查每一個上游
  $host_belong_sw[host_id].each do |port_data|
    port = port_data[:port]
    used = 0
    # 檢查此switch上游之host分別被assign多少
    UPSTREAM_INFO[port].each do |up_host_id|
      # 扣掉自己
      next if up_host_id == host_id
      up_host_data = $client_host[up_host_id]
      if up_host_data # 若此host已連線
        #puts "#{port}: #{host_id} assigned: #{up_host_data[:speed_assigned]}"
        used += up_host_data[:speed_assigned]
      end
    end
    # 扣掉此switch允許的總流量(should speed)
    remain = ($port_data[port][:should_spd] * UNIT_MEGA * MAX_BW_UTIL_RATE) - used
    if remain < max_allow
      max_allow = remain
    end
    #puts "#{port}已使用：#{used}，最大許可：#{($port_data[port][:should_spd] * UNIT_MEGA )}，剩餘許可：#{remain}"
  end
  #puts "給#{host_id}的最後流量：#{max_allow / 8.0} bytes"
  return max_allow / 8.0

end

def show_info
  #puts `clear`
  puts "===各switch port queue狀況與該port平均速度==="
  $client_sw.clone.each_pair do |id,data|
    len = data[:len] 
    bar_len = (len / CTRL_QUEUE_DRAW_BAR_DIV).ceil
    p_data = $port_data[id]
    current_util = ($port_data[id][:total_spd]/((data[:spd] > 0 ? data[:spd] : MAX_SPEED_M)*UNIT_MEGA.to_f)*100).floor
    if current_util <= 0
      total_util = 0
      recent_util = 0
    else
      p_data[:util_total] += current_util
      p_data[:util_cnt] += 1
      total_util = p_data[:util_total] / p_data[:util_cnt] 
      util_data = p_data[:recent_util]
      util_data << current_util
      if util_data.size > MAX_UTIL_RECORD
        util_data.shift
      end
      recent_util = util_data.reduce(:+) / util_data.size
    end
    limit = data[:spd] > 0 ? data[:spd] : MAX_SPEED_M
    printf("%8s,限：%3d M, 均：%8.3f M,商：%3d M,應：%3d M,CU: %3d %%,RU: %3d %%, TU: %3d %%, %5d ,%s\n",id,limit,$port_data[id][:avg_speed] / UNIT_MEGA.to_f,$port_data[id][:div_spd],$port_data[id][:should_spd],current_util,recent_util,total_util,len,"|"*bar_len)
  end
  puts "===各host speed狀況==="
  count = CTRL_DRAW_HOST_LINE_NUMBER
  $client_host.clone.each_pair do |id,data|
    count -= 1
    speed = data[:spd] / UNIT_MEGA.to_f
    assigned_speed = data[:speed_assigned] / UNIT_MEGA.to_f 
    bar_len = (speed / CTRL_DRAW_BAR_DIV).ceil
    printf("%8s, %8.3f Mbits,指派: %8.3f Mbits,速度變化：%9s,%s\n",id,speed,assigned_speed,data[:show_cmd],"|"*bar_len)
  end
  print "\n"*count if count > 0
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
