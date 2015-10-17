#!/usr/bin/env ruby 

require 'socket'
require 'thread'
require 'io/wait' # for IO#ready?

$DEBUG = true

if ARGV.size > 0
  SERVER_OPEN = ARGV.collect{|str| str.to_i }
else
  SERVER_OPEN = [5002,5003,5004,5005,5006,5007,5008]
end


$servers = {}


class SubServer
    def initialize(port)
        @port = port
        @socket_name = "./unix_sockets/s-#{port}.sock"
        `rm #{@socket_name}`
        @sock_serv = UNIXServer.new(@socket_name)
        create_process
    end

    def create_process
        @pid = Process.spawn('ruby',"server.rb","#{@port}","-s")
        @io_r = @sock_serv.accept
    end

    # 讀取最新的一行
    def read
        line = ''
        while line.empty?
            while @io_r.ready?
                line = @io_r.gets
            end
        end
        line
    end
    # 結束
    def terminate
        puts "傳送SIGINT給 PID = #{@pid}..."
        Process.kill(:SIGINT,@pid)
        Process.wait(@pid)
    end
    # 重設 
    def reset
        puts "重設#{@port}"
        Process.kill(:SIGINT,@pid)
        Process.wait(@pid)
        create_process
    end

end

def open_server(port)
    $servers[port] = SubServer.new(port)
end



def start_read_server_info
    stop_read_server_info
    $thr_reading = Thread.new do
        loop do
            puts "====各Server資訊===="
            $servers.each do |port,serv|
                print "Port #{port}:"
                puts serv.read
            end
            sleep 1
        end
    end
end

def stop_read_server_info
    $thr_reading.exit if $thr_reading.is_a? Thread
end


def process_cmd
    puts "請輸入指令："
    cmd = $stdin.gets
    case cmd
    when /show/
        start_read_server_info
    when /exit/
        $servers.each_value do |serv|
            serv.terminate
        end
        exit
    when /reset all/
        $servers.each_value {|serv| serv.reset}
        start_read_server_info
    when /reset ((\d+ )*\d+)/
        $1.split.each do |port_str|
            $servers[port_str.to_i].reset
        end
        start_read_server_info
    else 
        puts "無法識別的指令"
        return false
    end
    return true

end

# Signal處理：輸入指令
Signal.trap("QUIT") do
    stop_read_server_info
    while !process_cmd
        # 需要retry
    end
end

# 開啟所有server
SERVER_OPEN.each do |port|
    open_server port
end
# main
start_read_server_info
loop do
    sleep 1
end
