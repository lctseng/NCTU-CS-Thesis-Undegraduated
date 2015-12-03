#!/usr/bin/env ruby
# 前提：所有的switch都已經產生
# 目的：設置QoS Queue

require_relative 'qos-info'


def shell_exec(cmd,show = false)
  puts "Exec:#{cmd}" if show
  system cmd
end

# 寫入設定
if ARGV[0] !~ /__last__/i
  File.open("last_setup_mode.tmp",'w') do |f|
    f.puts ARGV[0]
  end
end

# 清除舊的QoS
if CLEAR_OLD
  puts "** 清除舊有QoS資訊 **"
  QOS_INFO.each_pair do |port,data|
    puts "清除QoS：#{port}"
    shell_exec("ovs-vsctl clear Port #{port} qos")
    data[:ingress_list].each do |eth|
      port = "#{data[:sw]}-eth#{eth}" 
      puts "清除QoS：#{port}"
      shell_exec("ovs-vsctl clear Port #{port} qos")

    end
  end
  shell_exec("ovs-vsctl -- --all destroy QoS")
  shell_exec("ovs-vsctl -- --all destroy Queue")
end
# 建立QoS
puts "** 建立QoS **"
QOS_INFO.each_pair do |port,data|
  puts "建立QoS：#{port}"
  qid = data[:eth]
  if defined?(NO_SPEED_LIMIT_FOR) && NO_SPEED_LIMIT_FOR.include?(port)
    max_spd = MAX_TOTAL_SPEED
  else
    max_spd = MAX_SPEED / UNIT_MEGA * 10**6
  end
  shell_exec %Q{
    ovs-vsctl -- set Port #{port} qos=@newqos -- \
    --id=@newqos create QoS type=linux-htb other-config:max-rate=#{MAX_TOTAL_SPEED} queues=#{qid}=@q#{qid} -- \
    --id=@q#{qid} create Queue other-config:max-rate=#{max_spd} -- 
  }
end
# 設定Link Delay 
puts "** 設定Link Delay **"
LINK_DELAY.each do |port,delay|
  puts "設定#{port}的delay為#{delay}"
  # 檢查是否有QoS
  if QOS_INFO.has_key? port
    if delay != '0ms'
      # 建立在1:1與1:(eth+1)之下
      [1,QOS_INFO[port][:eth].to_i+1].each do |handle|
        shell_exec  "tc qdisc add dev #{port} parent 1:#{handle} handle #{10+handle}: netem delay #{delay} limit 1000"
      end
    end
  else
    # 先清空
    shell_exec "tc qdisc del dev #{port} root"
    if delay != '0ms'
      # 建立在root底下
      shell_exec "tc qdisc add dev #{port} root handle 10: netem delay #{delay} limit 1000"

    end
  end
end

# 清除舊的flow table entry
if CLEAR_OLD
  puts "** 清除舊有flow table **"
  QOS_INFO.values.each do |data|
    sw = data[:sw]
    puts "清除flow table：#{sw}"
    shell_exec("ovs-ofctl del-flows #{sw}")
  end
end
# 設定新的flow table entry
puts "** 新增flow table entry**"
QOS_INFO.each_pair do |port,data|
  sw = data[:sw]
  data[:ingress_list].each do |in_port|
    puts "新增flow table entry：#{sw}，ingress_port：#{in_port}"
    for port in data[:udp_port]
      shell_exec("ovs-ofctl add-flow #{sw} udp,tp_dst=#{port},priority=1024,in_port=#{in_port},actions=set_queue:#{data[:eth]},normal")
      shell_exec("ovs-ofctl add-flow #{sw} tcp,tp_dst=#{port},priority=1024,in_port=#{in_port},actions=set_queue:#{data[:eth]},normal")
    end
  end
  shell_exec("ovs-ofctl add-flow #{sw} priority=0,actions=CONTROLLER:65535")
end

FIXED_FLOW_ENTRY.each do |entry|
  puts "新增額外entry：#{entry}"
  shell_exec("ovs-ofctl add-flow #{entry[:sw]} udp,tp_src=#{entry[:src_port]},priority=1024,in_port=#{entry[:in_port]},actions=output:#{entry[:out_port]}")
end

