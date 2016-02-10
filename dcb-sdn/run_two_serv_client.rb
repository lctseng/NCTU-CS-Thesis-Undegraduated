#!/usr/bin/env ruby 

require_relative 'config'
NO_TYPE_REQUIRED = true if !defined? NO_TYPE_REQUIRED
require 'qos-lib'

pipes = {}
children = {}
last_str = {}

$DEBUG = false

# Fork all monitors
server_ip = "172.16.0.1"
for n in [6,8,9]
  ip = "172.16.0.#{n}"
  port = 5000 + n
  puts "Starting:#{ip}"
  pipe = IO.pipe
  if pid = fork
    # parent
    children[ip] =  pid
    pipes[ip] = pipe
  else
    # child
    #$stdin.reopen pipe[0]
    $stdout.reopen pipe[1]
    Process.exec "ssh -t root@#{ip} 'cd monitor-mn/dcb-sdn;ruby client.rb __last__ #{server_ip} #{port} #{ip}'"
  end
end
server_ip = "172.16.0.2"
for n in [3,4,7]
  ip = "172.16.0.#{n}"
  port = 5000 + n
  puts "Starting:#{ip}"
  pipe = IO.pipe
  if pid = fork
    # parent
    children[ip] =  pid
    pipes[ip] = pipe
  else
    # child
    #$stdin.reopen pipe[0]
    $stdout.reopen pipe[1]
    Process.exec "ssh -t root@#{ip} 'cd monitor-mn/dcb-sdn;ruby client.rb __last__ #{server_ip} #{port} #{ip}'"
  end
end
# Read from all 
begin
  loop do
    print "========================\n\r"
    cnt = 0
    pipes.each do |ip,pipe|
      begin
        str = pipe[0].readline_nonblock
        print "#{ip}:#{str}\r"
        last_str[ip] = str
      rescue IO::WaitReadable,IO::EAGAINWaitReadable
        print "#{ip}:#{last_str[ip]}\r"
      rescue SystemExit, Interrupt, SignalException
        exit
      rescue EOFError
        print "#{ip}已關閉通訊！\n\r"
        pipes.delete ip
      end
    end
    sleep 0.1
  end
rescue SystemExit, Interrupt, SignalException
  print "結束中\n\r"
  print "等待children關閉\n\r"
  children.each_value do |pid|
    Process.kill("INT",pid)
    Process.wait pid
  end
end
