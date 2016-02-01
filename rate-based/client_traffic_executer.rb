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
  if RATE_BASED_WAIT_FOR_ACK
    sub_size = get_sub_size($io_type)
  else
    sub_size = ($size.to_f / PACKET_SIZE ).ceil 
  end
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
    if RATE_BASED_WAIT_FOR_ACK
      new_sub_size = get_sub_size($io_type)
      ack_req[:sub_size] = new_sub_size
      timing.start
      reply_req = send_and_wait_for_ack($sender,ack_req)
      #printf "ACK RTT: %9.4f ms\n",timing.end
      if reply_req[:extra] == "LOSS"
        $size += current_send
        done = false
      else
        sub_size = new_sub_size
        if done
          $stop = true
        end
        i += 1
      end
    else
      if done
        $stop = true
      end
      break
    end
    if $stop
      break
    end
  end


  ###
  puts "Exiting"
  $sender_control.exit
  $sender.close


else
  # //////////////////////
  # do receving
  # //////////////////////
  $sender = ReceiverProcess.connect($host,$port)

  ###
  # Send Init request
  init_req = {}
  init_req[:is_request] = true
  init_req[:type] = "recv init"
  init_req[:data_size] = $size
  init_req[:extra] = $io_type
  rep = send_and_wait_for_ack($sender,init_req)
  if RATE_BASED_WAIT_FOR_ACK
    sub_size = rep[:sub_size]
  else
    sub_size = ($size.to_f / PACKET_SIZE ).ceil
  end
  task_n = 0

  accu = $size
  # Recv loop
  loop do
    # read block
    got_ack_pkt = nil
    sub_n = 0
    loss = false
    current_read = 0

    # Sub data buffer
    sub_buf = [false] * sub_size
    if RATE_BASED_WAIT_FOR_ACK
      printf "Start Task: %5d，max sub size: %3d ",task_n,sub_size
    end
    while sub_n < sub_size
      data_req = extract_next_req($sender.target_sock)
      current_read += PACKET_SIZE
      if data_req[:type] != "recv data"
        if data_req[:type] == "recv ack"
          puts "提早收到ACK"
          got_ack_req = data_req
          loss = true
          break
        else
          puts data_req
          puts "收到預期外封包" 
        end
      end
      if data_req[:task_no] != task_n
        #puts "Task預期：#{task_n}，收到：#{data_req[:task_no]}"
        loss = true
        break
      end
      if !RATE_BASED_WAIT_FOR_ACK
        accu -= PACKET_SIZE
        puts "剩餘大小：#{accu}"
        if accu <= 0
          done = true
        end
      end
      data_sub_n = data_req[:sub_no][0] 
      sub_buf[data_sub_n] = true
      sub_n += 1
      # Check Done
      if RATE_BASED_WAIT_FOR_ACK
        if data_req[:extra] == "DONE"
          #puts "DATA DONE"
          for i in sub_n...sub_size
            sub_buf[i] = true
          end
          done = true
          break
        else
          done = false
        end
      end
    end
    # 檢查sub buf 
    if sub_buf.all? {|v| v } && ( CLIENT_LOSS_RATE == 0.0 || rand > CLIENT_LOSS_RATE )
      # 全都有
    else
      loss = true
    end
    # read ack 
    if RATE_BASED_WAIT_FOR_ACK 
      # read until an ack appear
      begin
        if got_ack_req
          data_ack_req = got_ack_req
          got_ack_req = nil
          current_read -= PACKET_SIZE
        else
          data_ack_req = extract_next_req($sender.target_sock)
        end
        #puts "ACK：收到：#{data_ack_req}"
      end while !(data_ack_req[:is_request] && data_ack_req[:type] == "recv ack")
      # send ack back
      req_to_reply(data_ack_req)
      if loss
        sub_buf.each_with_index do |r,i|
          puts i if !r
        end
        data_ack_req[:extra] = "LOSS"
        puts "重新開始：#{task_n}"
      else
        $size -= current_read
        data_ack_req[:extra] = "OK"
        task_n += 1
        puts "剩餘大小：#{$size}" if RATE_BASED_WAIT_FOR_ACK
        sub_size = data_ack_req[:sub_size]
      end
      #puts "Reply ACK：#{data_ack_req}"
      io_time = get_disk_io_time($io_type)
      #printf "IO Time: %7.5f\n",io_time
      sleep io_time
      $sender.send(pack_command(data_ack_req),0)
    end
    if !loss && done
      puts "DONE"
      break
    end

  end



end
