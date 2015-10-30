#!/usr/bin/env ruby 

require_relative 'qos-info'

pipes = {}
children = {}

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
    sleep 0.5
  end
end
# Read from all 
begin
  loop do
    puts "========================"
    pipes.each do |port,pipe|
      begin
        pipe[0].gets
        puts "#{port}:#{$_}"
      rescue IO::WaitReadable

      rescue EOFError
        puts "#{port}已關閉通訊！"
        pipes.delete port
      end
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
