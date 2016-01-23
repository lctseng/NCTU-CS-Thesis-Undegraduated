#!/usr/bin/env ruby
require_relative 'host-info'

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
PKACKET_VALIDATOR = "VALIDATOR"
DEBUG_TIMING = false
WRITE_RATE = 1.0
TRAFFIC_COUNT_ACK = true


# Contorller端設置
CTRL_QUEUE_DRAW_BAR_DIV = 60.0
CTRL_DRAW_BAR_DIV = 2.5 * (MAX_SPEED / (100*UNIT_MEGA))
CTRL_DRAW_HOST_LINE_NUMBER = 7
ENABLE_ASSIGN = true
ASSIGN_RATE = 0.9
CHECK_FORCE_ASSIGN_IDLE_RATE = 1.0 # 1.0 = disabled
CHECK_FORCE_ASSIGN_IDLE_HOST_COUNT = 2 # host count <= this number to enable force re-assign
MAX_UTIL_RECORD = 300
ENABLE_REDISTRIBUTE = true
RE_DISTRIBUTE_RATE = 0.9
RE_DISTRIBUTE_THRESHOLD = 5000
CTRL_BALANCE_THRESHOLD_RATE = 0.1
CTRL_BALANCE_DECREASE_VALUE = 50
CTRL_BALANCE_CHANGE_RATE = -0.5
CTRL_ASSIGN_BASELINE = 100000
CTRL_HOST_COUNT_LOG_BASE = 2.0
CTRL_SW_SPEED_LIMIT_ADJUST = 1.0 # 1.0 = precise

# Server
SERVER_RANDOM_FIXED_SEED = true
SERVER_LOSS_RATE = 0.0

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
CLI_WAIT_FOR_ACK = !DEBUG_TIMING
CLI_ACK_SLICE = 256 * UNIT_KILO
CLI_ACK_SLICE_PKT = (CLI_ACK_SLICE.to_f / PACKET_SIZE).ceil
CLIENT_LOSS_RATE = 0.0

# LOG 設置
HOST_LOG_NAME_FORMAT = "log/host_speed_%s.log"
HOST_LOG_NAME_JSON_FORMAT = "json/host_speed_%s.json"
SWITCH_LOG_NAME_FORMAT = "log/switch_info_%s.log"
SWITCH_LOG_NAME_JSON_FORMAT = "json/switch_%s_%s.json"



# DCB Mode
DCB_SERVER_BUFFER_PKT_SIZE = 20000 # server application memory buffer for 100000 pkts 
DCB_SERVER_BUFFER_STOP_THRESHOLD = DCB_SERVER_BUFFER_PKT_SIZE * 0.7
DCB_SERVER_BUFFER_GO_THRESHOLD = DCB_SERVER_BUFFER_PKT_SIZE * 0.5
DCB_SIGNAL_SENDER_PORT = 9001
DCB_PREMATURE_ACK = false # true is deprecated for DCB-SDN
DCB_CEHCK_MAJOR_NUMBER = true
DCB_SENDER_REQUIRE_ACK = true

# DCB-SDN
DCB_SDN_PREMATURE_ACK = DCB_PREMATURE_ACK
DCB_SDN_EXTRA_TOKEN_USED = !DCB_SENDER_REQUIRE_ACK ? 0 : 1
DCB_SDN_CTRL_ADDR = "172.16.0.253"
DCB_SDN_CTRL_PORT = 10100
DCB_SDN_MAX_TOKEN = 18000
DCB_SDN_MAX_SWITCH_QUEUE_LENGTH = 925

DCB_RECEIVER_FEEDBACK_THRESHOLD =  15000#DCB_SDN_EXTRA_TOKEN_USED + CLI_ACK_SLICE_PKT 
DCB_SWITCH_FEEDBACK_THRESHOLD =  1

DCB_SDN_MAX_TOKEN_REQ = 300

# Rate-based
RATE_BASED_CTRL_ADDR = "172.16.0.253"
RATE_BASED_CTRL_PORT = "10200"
RATE_BASED_CTRL_MSG_LEN = 100


RATE_BASED_WAIT_FOR_ACK = true

RATE_BASED_SHOW_INTERVAL = 0.1
RATE_BASED_SWITCH_MONITOR_INTERVAL = 0.01

RATE_BASED_SEND_INTERVAL = 0.005
RATE_BASED_BASE_SPEED_PKTI = 0.05

RATE_BASED_SWITCH_SCAN_INTERVAL = 0.01

RATE_BASED_ASSIGN_RATE = 0.7

RATE_BASED_SWITCH_INTERVAL_CONVERT_RATE = RATE_BASED_SEND_INTERVAL / RATE_BASED_SWITCH_MONITOR_INTERVAL




PASSIVE_PORT_TO_IP = {
  5001 => '172.16.0.1',
  5002 => '172.16.0.2',
  5003 => '172.16.0.3',
  5004 => '172.16.0.4',
  5005 => '172.16.0.5',
  5006 => '172.16.0.6',
  5007 => '172.16.0.7',
  5008 => '172.16.0.8'
}

# QoS資料
QOS_INFO = {}
def add_qos_info(sw,eth,ingress_list,udp_port = 5001..5008)
  QOS_INFO["#{sw}-eth#{eth}"] = {eth: eth,ingress_list: ingress_list,sw: sw,udp_port: udp_port}
end

LINK_DELAY = {}
FIXED_FLOW_ENTRY = []

if !defined?(NO_TYPE_REQUIRED) || !NO_TYPE_REQUIRED
  _mode = ARGV[0]
  if _mode.nil?
    puts "Please add mode as first argument! or use '<program> __last__' to use last settings"
    exit
  end

  if _mode
    if _mode =~ /__last__/i
      File.open('/root/last_setup_mode.tmp') do |f|
        str = f.gets
        _mode = str if str
      end
    else
      File.open('/root/last_setup_mode.tmp','w') do |f|
        f.puts _mode
      end
    end
  end
else
  $stderr.puts "NOTICE: No mode is specfied"
  _mode = nil
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
  RECEIVER_HOSTS = {
    HOST[1] => [HOST[2],HOST[3]],
    HOST[5] => [HOST[4]]
  }

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
  # Forward
  add_qos_info('s1','3',[1,2])
  add_qos_info('s2','1',[4])
  add_qos_info('s2','2',[3])
  add_qos_info('s3','3',[1,2,4])
  add_qos_info('s4','3',[1,2])
  # Backward
  # Lower
  # s1 
  add_qos_info('s1','2',[3],5005..5005)
  add_qos_info('s1','1',[3],5001..5001)
  # s2 
  add_qos_info('s2','3',[2],[5001,5005])
  # Upper
  # s2
  add_qos_info('s2','4',[1],[5003,5004,5007,5008])
  # s3 
  add_qos_info('s3','1',[3],5003..5003)
  add_qos_info('s3','2',[3],5007..5007)
  add_qos_info('s3','4',[3],[5004,5008])
  # s4
  add_qos_info('s4','1',[3],5004..5004)
  add_qos_info('s4','2',[3],5008..5008)

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
  STARTING_ORDER = ["s2-eth1","s3-eth3","s4-eth3","s2-eth2","s1-eth3",
                    "s1-eth2","s1-eth1","s2-eth3",
                    "s4-eth1","s4-eth2","s3-eth4","s3-eth1","s3-eth2","s2-eth4"]
  RECEIVER_HOSTS = {
    HOST[2] => [HOST[3],HOST[4],HOST[7],HOST[8]],
    HOST[6] => [HOST[1],HOST[5]]
  }
  # define senders
  PACKET_SENDERS = {
    # Forward
    "#{HOST[2]}:5003" => HOST[3],
    "#{HOST[2]}:5004" => HOST[4],
    "#{HOST[2]}:5007" => HOST[7],
    "#{HOST[2]}:5008" => HOST[8],
    
    "#{HOST[6]}:5001" => HOST[1],
    "#{HOST[6]}:5005" => HOST[5],
    # Backward
    "#{HOST[3]}:5003" => HOST[2],
    "#{HOST[4]}:5004" => HOST[2],
    "#{HOST[7]}:5007" => HOST[2],
    "#{HOST[8]}:5008" => HOST[2],

    "#{HOST[1]}:5001" => HOST[6],
    "#{HOST[5]}:5005" => HOST[6]
  }
  # define packet flow
  PACKET_FLOWS = {
    # Forward
    "#{HOST[2]}:5003" => ["s3-eth3","s2-eth1",HOST[2]],
    "#{HOST[2]}:5004" => ["s4-eth3","s3-eth3","s2-eth1",HOST[2]],
    "#{HOST[2]}:5007" => ["s3-eth3","s2-eth1",HOST[2]],
    "#{HOST[2]}:5008" => ["s4-eth3","s3-eth3","s2-eth1",HOST[2]],
    
    "#{HOST[6]}:5001" => ["s1-eth3","s2-eth2",HOST[6]],
    "#{HOST[6]}:5005" => ["s1-eth3","s2-eth2",HOST[6]],
    # Backward
    "#{HOST[3]}:5003" => ["s2-eth4","s3-eth1",HOST[3]],
    "#{HOST[4]}:5004" => ["s2-eth4","s3-eth4","s4-eth1",HOST[4]],
    "#{HOST[7]}:5007" => ["s2-eth4","s3-eth2",HOST[7]],
    "#{HOST[8]}:5008" => ["s2-eth4","s3-eth4","s4-eth2",HOST[8]],

    "#{HOST[1]}:5001" => ["s2-eth3","s1-eth1",HOST[1]],
    "#{HOST[5]}:5005" => ["s2-eth3","s1-eth2",HOST[5]]

  }

when /linearTopoK4N2-single/i


  # Forward
  add_qos_info('s1','1',[2,3])
  add_qos_info('s2','3',[1,2,4])
  add_qos_info('s3','3',[1,2,4])
  add_qos_info('s4','3',[1,2])
  # Backward 
  # s1 
  #add_qos_info('s1','2',[1],5005..5005)
  #add_qos_info('s1','3',[1],[5002,5003,5004,5006,5007,5008])
  # s2
  #add_qos_info('s2','1',[3],5002..5002)
  #add_qos_info('s2','2',[3],5006..5006)
  #add_qos_info('s2','4',[3],[5003,5004,5007,5008])
  # s3
  #add_qos_info('s3','1',[3],5003..5003)
  #add_qos_info('s3','2',[3],5007..5007)
  #add_qos_info('s3','4',[3],[5004,5008])
  # s4
  #add_qos_info('s4','1',[3],5004..5004)
  #add_qos_info('s4','2',[3],5008..5008)


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
  
  RECEIVER_HOSTS = {
    HOST[1] => [HOST[2],HOST[3],HOST[4],HOST[5],HOST[6],HOST[7],HOST[8]]
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

# Compute host upstream  switch
HOST_UPSTREAM_SWITCH = {}
if defined? UPSTREAM_INFO
  UPSTREAM_INFO.each do |sw,host_array|
    host_array.each do |host|
      HOST_UPSTREAM_SWITCH[host] ||= []
      HOST_UPSTREAM_SWITCH[host] << sw
    end
  end
end
# Compute host upstream host 
HOST_UPSTREAM_HOST = {}
if defined? RECEIVER_HOSTS
  RECEIVER_HOSTS.each do |recv,hosts|
    hosts.each do |host|
      HOST_UPSTREAM_HOST[host] = recv
    end
  end
end
# Compute  
TARGET_HOSTS_ID = {}
if defined? PACKET_SENDERS
  PACKET_SENDERS.each do |target,sender|
    if !TARGET_HOSTS_ID.has_key? sender
      TARGET_HOSTS_ID[sender] = []
    end
    TARGET_HOSTS_ID[sender] << target
  end
end
# packet flow with switch only 
if defined? PACKET_FLOWS
  PACKET_FLOWS_SW_ONLY = {}
  PACKET_FLOWS.each do |key,array|
    PACKET_FLOWS_SW_ONLY[key] = array[0,array.size-1]
  end
end
# switch port to senders id 
if defined? PACKET_FLOWS_SW_ONLY
  SWITCH_PORT_PASSING_HOST = {}
  PACKET_FLOWS_SW_ONLY.each do |host,sw_list|
    sw_list.each do |port|
      if !SWITCH_PORT_PASSING_HOST.has_key? port
        SWITCH_PORT_PASSING_HOST[port] = [host]
      else
        SWITCH_PORT_PASSING_HOST[port] << host
      end
    end
  end
end
