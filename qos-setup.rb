#!/usr/bin/env ruby
# 前提：所有的switch都已經產生
# 目的：設置QoS Queue

require './qos-info.rb'

# 清除舊的QoS
if CLEAR_OLD
    puts "** 清除舊有QoS資訊 **"
    QOS_INFO.each_pair do |port,data|
        puts "清除QoS：#{port}"
        IO.popen("ovs-vsctl clear Port #{port} qos")
        data[:ingress_list].each do |eth|
            port = "#{data[:sw]}-eth#{eth}" 
            puts "清除QoS：#{port}"
            IO.popen("ovs-vsctl clear Port #{port} qos")

        end
    end
    IO.popen("ovs-vsctl -- --all destroy QoS")
    IO.popen("ovs-vsctl -- --all destroy Queue")
end
# 建立QoS
puts "** 建立QoS **"
QOS_INFO.each_pair do |port,data|
    puts "建立QoS：#{port}"
    qid = data[:eth]
    IO.popen %Q{
    ovs-vsctl -- set Port #{port} qos=@newqos -- \
    --id=@newqos create QoS type=linux-htb other-config:max-rate=#{MAX_TOTAL_SPEED} queues=#{qid}=@q#{qid} -- \
    --id=@q#{qid} create Queue other-config:max-rate=#{MAX_SPEED} -- 
    }
end
# 清除舊的flow table entry
if CLEAR_OLD
    puts "** 清除舊有flow table **"
    QOS_INFO.values.each do |data|
        sw = data[:sw]
        puts "清除flow table：#{sw}"
        IO.popen("ovs-ofctl del-flows #{sw}")
    end
end
# 設定新的flow table entry
puts "** 新增flow table entry**"
QOS_INFO.each_pair do |port,data|
    sw = data[:sw]
    data[:ingress_list].each do |in_port|
        puts "新增flow table entry：#{sw}，ingress_port：#{in_port}"
        IO.popen("ovs-ofctl add-flow #{sw} udp,priority=1024,in_port=#{in_port},actions=set_queue:#{data[:eth]},normal")
    end
    IO.popen("ovs-ofctl add-flow #{sw} priority=0,actions=CONTROLLER:65535")
end

