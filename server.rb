#!/usr/bin/env ruby 

require 'socket'

$DEBUG = true

PACKET_SIZE = 1450

port = ARGV[0].to_i
use_sock = ARGV[1] =~ /-s/

receiver = UDPSocket.new
receiver.bind("0.0.0.0",port)

# Output socket
if use_sock
    puts "使用UNIX Socket輸出"
    $output = UNIXSocket.open "./unix_sockets/s-#{port}.sock"  
    Signal.trap("QUIT") do
        # Dont stop the server, the signal QUIT is send to collection program
    end
else
    puts "使用標準輸出"
    $output = $stdout
end


$cnt = 0
$loss = 0
$size_total = 0.0
$last_size = 0.0
$loss_cnt = {}

Thread.new do 
    loop do
        diff = $size_total - $last_size
        $last_size = $size_total
        $output.printf("總大小： %.6f Mbit，",$size_total * 8.0 / 1000000.0)
        $output.puts "區間傳輸大小：#{(sprintf("%3.3f",diff * 8 / 1000000.0))} Mbit，遺失封包數：#{$loss}"
        sleep 1
    end
end


begin
    loop do
        str = receiver.recvfrom(PACKET_SIZE)[0]
        size_plus = false
        str =~ /\A(\d+)/

        n = $1.to_i
        #puts "收到：#{n}"
        if n > $cnt
            diff = n- $cnt
            #puts "遺失：#{diff}，區間：#{$cnt}~#{n}"
            for i in $cnt...n
                $loss_cnt[i] = true
            end
            $loss += diff
            $cnt = n + 1
            size_plus = true
        elsif n < $cnt
            #puts "順序錯亂：期望#{$cnt}，收到#{n}"
            if $loss_cnt.has_key? n
                $loss_cnt.delete n
                $loss -= 1
                size_plus = true
            else
                puts "重複抵達的封包：#{n}"
            end
        else
            $cnt += 1
            size_plus = true
        end
        $size_total += str.size if size_plus
    end
rescue SystemExit, Interrupt
    puts "receiver結束"
end
