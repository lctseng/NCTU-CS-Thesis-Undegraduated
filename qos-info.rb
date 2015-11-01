#!/usr/bin/env ruby
require_relative 'host-info'

$DEBUG = true
# 常數
UNIT_KILO = 10**3
ENABLE_CONTROL = true
UNIT_MEGA = UNIT_KILO**2
MAX_TOTAL_SPEED = UNIT_KILO**3 # 整體最大速度
MAX_SPEED = 100*UNIT_MEGA # 最大速度
MAX_SPEED_M = MAX_SPEED / UNIT_MEGA
CLEAR_OLD = true # 是否刪除舊資料
MAX_NOTIFICATION_INTERVAL = 0.1
MAX_BW_UTIL_RATE = 0.95
DATA_PROTOCOL = ENABLE_CONTROL ? :udp : :tcp
PACKET_SIZE = 1400
MONITOR_SHOW_INFO = true
LINE_UTIL_RATE = MAX_BW_UTIL_RATE

# Contorller端設置
CTRL_QUEUE_DRAW_BAR_DIV = 60.0
CTRL_DRAW_BAR_DIV = 2.5 * (MAX_SPEED / (100*UNIT_MEGA))
CTRL_DRAW_HOST_LINE_NUMBER = 7
ENABLE_ASSIGN = true
ASSIGN_RATE = 0.7
CHECK_FORCE_ASSIGN_IDLE_RATE = 0.5 # 1.0 = disabled
CHECK_FORCE_ASSIGN_IDLE_HOST_COUNT = 2 # host count <= this number to enable force re-assign
MAX_UTIL_RECORD = 300
ENABLE_REDISTRIBUTE = true
RE_DISTRIBUTE_RATE = 0.7
RE_DISTRIBUTE_THRESHOLD = 5000
CTRL_BALANCE_THRESHOLD_RATE = 0.5
CTRL_BALANCE_DECREASE_VALUE = 30
CTRL_BALANCE_CHANGE_RATE = -1.0
CTRL_ASSIGN_BASELINE = 1000
CTRL_HOST_COUNT_LOG_BASE = 2.0
CTRL_SW_SPEED_LIMIT_ADJUST = 1.0 # 1.0 = precise

# Client端設置
CLIENT_RANDOM_MODE = :pattern
CLIENT_RANDOM_SLEEP_RANGE = 5
CLIENT_RANDOM_SEND_TIME_RANGE = 10
CLIENT_RANDOM_SEND_SIZE_RANGE = 100000000
CLIENT_RANDOM_FIXED_SEED = true
CLIENT_RANDOM_START = 0
CLIENT_STOP_SIZE_BYTE = 2000*UNIT_MEGA
CLIENT_PATTERN_NAME_FORMAT = "pattern/client_%s.pattern"
CLI_SEND_INTERVAL = 0.005
CLI_SEND_DETECT_INTERVAL = CLI_SEND_INTERVAL / 10.0

# LOG 設置
HOST_LOG_NAME_FORMAT = "log/host_speed_%s.log"
HOST_LOG_NAME_JSON_FORMAT = "json/host_speed_%s.json"
SWITCH_LOG_NAME_FORMAT = "log/switch_info_%s.log"
SWITCH_LOG_NAME_JSON_FORMAT = "json/switch_%s_%s.json"



# QoS資料
QOS_INFO = {}
def add_qos_info(sw,eth,ingress_list,udp_port = 5001..5008)
  QOS_INFO["#{sw}-eth#{eth}"] = {eth: eth,ingress_list: ingress_list,sw: sw,udp_port: udp_port}
end

LINK_DELAY = {}



_mode = ARGV[0]
if _mode.nil?
  puts "Please add mode as forst argument! or use '<program> __last__' to use last settings"
  exit
end

if _mode &&  _mode =~ /__last__/i
  File.open("last_setup_mode.tmp") do |f|
    str = f.gets
    _mode = str if str
  end
end




case _mode
when /simple/
  add_qos_info('s1','1',[2,3]) # Switch名稱、output port(QoS限制此port之流量)、input ports
  UPSTREAM_INFO = {
    "s1-eth1" => [HOST[2],HOST[3]]
  }
  UPSTREAM_SWITCH = {
  }
  STARTING_ORDER = ["s1-eth1"]


when /flowbase/
  add_qos_info('s1','1',[2,3])
  add_qos_info('s1','5',[4])
  UPSTREAM_INFO = {
    "s1-eth1" => [HOST[2],HOST[3]],
    "s1-eth5" => [HOST[4]]
  }
  UPSTREAM_SWITCH = {
  }
  STARTING_ORDER = ["s1-eth1","s1-eth5"]

  # Simplest Topo
when /switchspeed1/
  add_qos_info('s1','1',[2,3])
  add_qos_info('s2','1',[2])
  UPSTREAM_INFO = {
    "s1-eth1" => [HOST[2],HOST[3]],
    "s2-eth1" => [HOST[2]]
  }
  UPSTREAM_SWITCH = {
    "s1-eth1" => ["s2-eth1"]
  }
  STARTING_ORDER = ["s1-eth1","s2-eth1"]
  # Multi-host 
when /switchspeed2/
  add_qos_info('s1','1',[2,3])
  add_qos_info('s2','1',[2,3])
  add_qos_info('s1','5',[4])
  UPSTREAM_INFO = {
    "s1-eth1" => [HOST[2],HOST[3],HOST[4]],
    "s2-eth1" => [HOST[2],HOST[4]],
    "s1-eth5" => [HOST[5]]
  }
  UPSTREAM_SWITCH = {
    "s1-eth1" => ["s2-eth1"]
  }
  STARTING_ORDER = ["s1-eth1","s2-eth1","s1-eth5"]
  # Linear topo test: k=2 n= 2
when /linearTopoK2N2/i
  add_qos_info('s1','1',[2,3])
  add_qos_info('s2','3',[1,2])
  UPSTREAM_INFO = {
    "s1-eth1" => [HOST[2],HOST[3],HOST[4]],
    "s2-eth3" => [HOST[2],HOST[4]]
  }
  UPSTREAM_SWITCH = {
    "s1-eth1" => ["s2-eth3"]
  }
  STARTING_ORDER = ["s1-eth1","s2-eth3"]
  # linear k = 4 ,n = 2
when /linearTopoK4N2-multi/i
  add_qos_info('s1','3',[1,2])
  add_qos_info('s2','1',[4])
  add_qos_info('s2','2',[3])
  add_qos_info('s3','3',[1,2,4])
  add_qos_info('s4','3',[1,2])
  UPSTREAM_INFO = {
    "s1-eth3" => [HOST[1],HOST[5]],
    "s2-eth1" => [HOST[3],HOST[4],HOST[7],HOST[8]],
    "s2-eth2" => [HOST[1],HOST[5]],
    "s3-eth3" => [HOST[3],HOST[4],HOST[7],HOST[8]],
    "s4-eth3" => [HOST[4],HOST[8]]

  }
  UPSTREAM_SWITCH = {
    "s2-eth1" => ["s3-eth3","s4-eth3"],
    "s2-eth2" => ["s1-eth3"],
    "s3-eth3" => ["s4-eth3"]
  }
  STARTING_ORDER = ["s2-eth1","s3-eth3","s4-eth3","s2-eth2","s1-eth3"]

when /linearTopoK4N2-single/i
  # Forward
  add_qos_info('s1','1',[2,3])
  add_qos_info('s2','3',[1,2,4])
  add_qos_info('s3','3',[1,2,4])
  add_qos_info('s4','3',[1,2])
  # Backward  
  #add_qos_info('s1','2',[1])

  #NO_SPEED_LIMIT_FOR = ["s2-eth3","s3-eth3","s4-eth3"]


  UPSTREAM_INFO = {
    # Forward
    "s1-eth1" => [HOST[2],HOST[3],HOST[4],HOST[5],HOST[6],HOST[7],HOST[8]],
    "s2-eth3" => [HOST[2],HOST[3],HOST[4],HOST[6],HOST[7],HOST[8]],
    "s3-eth3" => [HOST[3],HOST[4],HOST[7],HOST[8]],
    "s4-eth3" => [HOST[4],HOST[8]],
    # Backward
    #"s1-eth2" => [HOST[1]],
  }
  UPSTREAM_SWITCH = {
    # Forward
    "s1-eth1" => ["s2-eth3","s3-eth3","s4-eth3"],
    "s2-eth3" => ["s3-eth3","s4-eth3"],
    "s3-eth3" => ["s4-eth3"]
    # Backward
  }
  ## STARTING ORDER 
  MULTIPLE_STARTING = true
  STARTING_ORDER = []
  # Forward
  STARTING_ORDER << ["s1-eth1","s2-eth3","s3-eth3","s4-eth3"]
  # Backward
  #STARTING_ORDER << ["s1-eth2"]



  # Delays
  default_delay = '0ms'
  LINK_DELAY.merge!({
    "s1-eth1" => default_delay,
    "s1-eth2" => default_delay,
    "s1-eth3" => default_delay,
    "s2-eth1" => default_delay,
    "s2-eth2" => default_delay,
    "s2-eth3" => default_delay,
    "s2-eth4" => default_delay,
    "s3-eth1" => default_delay,
    "s3-eth2" => default_delay,
    "s3-eth3" => default_delay,
    "s3-eth4" => default_delay,
    "s4-eth1" => default_delay,
    "s4-eth2" => default_delay,
    "s4-eth3" => default_delay 
  })

end

