#!/usr/bin/env ruby 

require_relative 'config'
require 'socket'
require 'thread'
require 'fileutils'
require 'qos-lib'

require 'common'
require 'sender_process'








  



$host = ARGV[1]
$port = ARGV[2].to_i
$host_ip = ARGV[3]
$command = ARGV[4]
$size = ARGV[5].to_i
$io_type = ARGV[6].to_i
if CLIENT_RANDOM_FIXED_SEED
  srand($port)
end
if !$host_ip
  puts "Must specify client IP"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [cmd] [size] [io_type]"
  exit
end
if $size <= 0
  puts "Size need to > 0"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [cmd] [size] [io_type]"
  exit
end
if $io_type <= 0
  puts "IO type need to > 0"
  puts "Usage: client [mode] [target_ip] [target_port] [client_ip] [cmd] [size] [io_type]"
  exit
end



timing = Timing.start
if $command == "write"
  # //////////////////////
  # do sending
  # //////////////////////

  $sender = SenderProcess.connect($host,$port)
  $sender_control = Thread.new do
    $sender.run_control_loop
  end

  ### 
  i = 0
  ack_req = {}
  ack_req[:is_request] = true
  ack_req[:type] = "send ack"
  # Data Req
  data_req = {}
  data_req[:is_request] = true
  data_req[:type] = "send data"
  sub_size = get_sub_size($io_type)
  # Send Init request
  init_req = {}
  init_req[:is_request] = true
  init_req[:type] = "send init"
  init_req[:data_size] = $size
  init_req[:sub_size] = sub_size
  init_req[:extra] = $io_type
  send_and_wait_for_ack($sender,init_req)
  # Start Data Packet
  loop do
    current_send = 0
    done = false
    sub_size.times do |j|
      data_req[:task_no] = i
      data_req[:sub_no] = [j]
      $size -= PACKET_SIZE
      current_send += PACKET_SIZE
      if $size <= 0
        data_req[:extra] = "DONE"
        done = true
      else
        data_req[:extra] = "CONTINUE"
      end
      $sender.send(pack_command(data_req),0)
      if done
        #puts "pre-DONE"
        break
      end
    end
    # Update sub size
    sub_size = get_sub_size($io_type)
    if RATE_BASED_WAIT_FOR_ACK
      ack_req[:sub_size] = sub_size
      timing.start
      reply_req = send_and_wait_for_ack($sender,ack_req)
      #printf "ACK RTT: %9.4f ms\n",timing.end
      if reply_req[:extra] == "LOSS"
        $size += current_send
        done = false
      else
        if done
          $stop = true
        end
        i += 1
      end
    else
      if done
        $stop = true
      end
      i += 1
    end
    if $stop
      break
    end
  end


  ###

  $sender_control.exit
  $sender.close


else
  # //////////////////////
  # do receving
  # //////////////////////
end
