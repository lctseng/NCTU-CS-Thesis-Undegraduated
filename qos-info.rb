#!/usr/bin/env ruby
require './host-info.rb'

$DEBUG = true
# 常數
MAX_TOTAL_SPEED = 1000*1000*1000 # 整體最大速度
MAX_SPEED = 100*1000*1000 # 最大速度
MAX_SPEED_M = MAX_SPEED / 1000000
CLEAR_OLD = true # 是否刪除舊資料
_mode = ARGV[0]

# QoS資料
QOS_INFO = {}
def add_qos_info(sw,eth,ingress_list)
    QOS_INFO["#{sw}-eth#{eth}"] = {eth: eth,ingress_list: ingress_list,sw: sw}
end

LINK_DELAY = {}

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
    add_qos_info('s1','1',[2,3])
    add_qos_info('s2','3',[1,2,4])
    add_qos_info('s3','3',[1,2,4])
    add_qos_info('s4','3',[1,2])
    UPSTREAM_INFO = {
        "s1-eth1" => [HOST[2],HOST[3],HOST[4],HOST[5],HOST[6],HOST[7],HOST[8]],
        "s2-eth3" => [HOST[2],HOST[3],HOST[4],HOST[6],HOST[7],HOST[8]],
        "s3-eth3" => [HOST[3],HOST[4],HOST[7],HOST[8]],
        "s4-eth3" => [HOST[4],HOST[8]]
        
    }
    UPSTREAM_SWITCH = {
        "s1-eth1" => ["s2-eth3","s3-eth3","s4-eth3"],
        "s2-eth3" => ["s3-eth3","s4-eth3"],
        "s3-eth3" => ["s4-eth3"]
    }
    STARTING_ORDER = ["s1-eth1","s2-eth3","s3-eth3","s4-eth3"]
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

