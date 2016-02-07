#!/usr/bin/env ruby 

require_relative 'config'
require 'qos-info'
require 'thread'
require 'common'

pipes = {}
children = {}


# Record Controller Traffic
thr_ctrl_traffic = Thread.new do
  file = File.new("log/ctrl_traffic","w")
  interval = IntervalWait.new
  last = 0
  loop do
    interval.sleep 1
    IO.popen("ovs-ofctl dump-flows s1 | grep cookie=0x0 | grep tp_dst=#{RATE_BASED_CTRL_PORT}") do |result| 
      str = result.read
      if str =~ /n_bytes=(\d+)/
        current = $1.to_i
        diff = current - last
        last = current
        spd = diff
        file.puts "#{Time.now.to_f} #{spd}"
      end
    end
  end
end

# Fork all monitors
switches = []
if defined? MULTIPLE_STARTING
  switches = STARTING_ORDER.flatten
else
  switches = STARTING_ORDER
end
switches.each do |port|
  if port =~/(.*)-eth(.*)/
    puts "Starting:#{port}"
    sw = $1
    eth = $2
    pipe = IO.pipe
    if pid = fork
      # parent
      children[port] =  pid
      pipes[port] = pipe
    else
      # child
      $stdin.reopen pipe[0]
      $stdout.reopen pipe[1]
      Process.exec "./monitor-mn.rb #{sw} #{eth}"
    end
    sleep 0.01
  end
end
# Read from all 
begin
  last_text = {}
  loop do
    puts "========================"
    text = []
    pipes.each do |port,pipe|
      begin
        pipe[0].gets
        str = "#{port}:#{$_}"
        text << str
        last_text[port] = str
      rescue IO::WaitReadable
        text << last_text[port]
      rescue EOFError
        puts "#{port}已關閉通訊！"
        pipes.delete port
      end
    end
    text.each do |str|
      puts str
    end
  end
rescue SystemExit, Interrupt
  puts "結束中"
  puts "等待children關閉"
  children.each_value do |pid|
    Process.kill("INT",pid)
    Process.wait pid
  end
end
