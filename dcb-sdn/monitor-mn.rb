#!/usr/bin/env ruby 

require_relative 'config'

require 'socket'
NO_TYPE_REQUIRED = true
require 'qos-info'
require 'control_api'
require 'token_adder'

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


class SwitchMonitor
  include TokenAdder
  def initialize(id)
    @id = id
    @token_buf = 0
    control_api = ControlAPI.new("127.0.0.1",@id,"")
    register_control_api(control_api)
  end

  def add_token(n)
    @token_buf += n
    if @token_buf >= DCB_SWITCH_FEEDBACK_THRESHOLD
      control_add_token(@token_buf)
      @token_buf = 0
    end
  end

end


$monitor = SwitchMonitor.new($port)
$monitor.add_token(DCB_SDN_MAX_SWITCH_QUEUE_LENGTH)

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

    if len >= 0 
      # 畫圖
      bar_len = (len / 20.0).ceil
      printf("%5d,速度上限：%3d Mbits, 區間已送出: %4d,Queue:%s\n",len,data[:spd],sent_diff,"|"*bar_len) if MONITOR_SHOW_INFO
    end
    $monitor.add_token(sent_diff)
    sleep MONITOR_INTERVAL

  end
rescue SystemExit, Interrupt

end
