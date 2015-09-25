#!/usr/bin/env ruby 

require 'socket'
require './host-info.rb'

$DEBUG = true

PACKET_SIZE = 1450
SEND_INTERVAL = 0.001
INIT_SPEED_PER_SECOND = 0*1000 # 80 Kbit (10 KB)
INIT_SPEED_PER_INTERVAL = INIT_SPEED_PER_SECOND * SEND_INTERVAL





# Controller
puts "連接Controller中..."
$controller_sock = TCPSocket.new CONTROLLER_IP_HOST,CONTROLLER_PORT
$controller_sock.puts "host 0"
puts "Controller已連接！"



sender = UDPSocket.new

host = ARGV[0]
port = ARGV[1].to_i


sender.connect(host,port)

$running = true
$speed = INIT_SPEED_PER_INTERVAL
$total_send = 0
$interval_send = 0
$speed_report = 0

$delay_send = 0

# 速度偵測
thr_detect = Thread.new do
    loop do
        $speed_report = $interval_send
        printf("總共傳輸：%.6f Mbit，當前速度：%.3f Mbit/s\n",$total_send*8.0/1000000,$interval_send * 8.0 /1000000 )
        $interval_send = 0
        sleep 1
    end
end
# 連接監測器
thr_monitor = Thread.new do
    while line = $controller_sock.gets
        case line
        when /spd/
            $controller_sock.puts "#{$speed_report * 8.0 }"
        when /add/
            data = line.split
            eval "$speed = $speed #{data[1]}"
        when /mul/
            data = line.split
            eval "$speed = ($speed * #{data[1]}).round"
        when /assign/
            spd = line.split[1].to_i
            $speed = spd * SEND_INTERVAL
        end
    end
end


begin
    cnt = 0
    loop do
        $delay_send += $speed
        if $delay_send >= PACKET_SIZE
            pkts = $delay_send / PACKET_SIZE
            $delay_send %= PACKET_SIZE
            for i in 0...pkts
                info = "#{cnt} "
                data =  info + "0" * (PACKET_SIZE - info.size)
                send = sender.send(data,0)
                $total_send += send
                $interval_send += send
                cnt += 1
            end
        end
        sleep SEND_INTERVAL
    end
rescue SystemExit, Interrupt 
    $running = false
    thr_monitor.exit
    thr_detect.exit
    $controller_sock.puts "close"
    puts "終止傳輸，再按一次Ctrl+C結束程式"
    printf("總共傳輸：%.6f Mbit\n",($total_send*8.0)/1000000 )
end
loop do
    sleep 1
end
