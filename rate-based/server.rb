#!/usr/bin/env ruby 

require_relative 'config'

require 'socket'
require 'thread'
require 'qos-lib'
require 'common'
require 'sender_process'

STATISTIC_INTERVAL = 0.2
IO_TYPE_NAME = {
  nil => " ",
  1 => "L",
  2 => "S",
}

SERVER_OPEN_PORT_RANGE = 5001..5008
#SERVER_OPEN_PORT_RANGE = 5005..5005
#SERVER_OPEN_PORT_RANGE = 5002..5002
#SERVER_OPEN_PORT_RANGE = 5008..5008
#SERVER_OPEN_PORT_RANGE = 5005..5008

if SERVER_RANDOM_FIXED_SEED
  srand(0)
end

$host_ip = ARGV[1]
if !$host_ip
  puts "Host IP required"
  exit
end


def run_recv_loop(pkt_handler,ack_req)
  port = pkt_handler.dst_port 
  # IO type
  $io_types[port] = io_type = ack_req[:extra].to_i
  # Compute loop number
  ack_cnt = (ack_req[:data_size].to_f / CLI_ACK_SLICE ).ceil
  # Reply Ack
  req_to_reply(ack_req)
  sz = pkt_handler.send(pack_command(ack_req),0)
  if TRAFFIC_COUNT_ACK
    $total_tx[port] += sz
  end
  # Prepare
  task_n = 0
  done = false
  loop do # receive loop
    # read block
    got_ack_req = nil
    sub_n = 0
    loss = false
    current_read = 0

    # Sub data buffer
    sub_buf = [false] * CLI_ACK_SLICE_PKT

    while sub_n < CLI_ACK_SLICE_PKT
      data_req = parse_command(pkt_handler.recv(PACKET_SIZE))
      current_read += PACKET_SIZE
      if data_req[:type] != "send data"
        if data_req[:type] == "send ack"
          #puts "提早收到ACK"
          got_ack_req = data_req
          #@pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT - 1 - sub_n
          loss = true
          break
        else
          puts "收到預期外封包:#{data_req}" 
          req_to_reply(data_req)
          pkt_handler.send(pack_command(data_req),0)
        end
      end
      if data_req[:task_no] != task_n
        puts "Task預期：#{task_n}，收到：#{data_req[:task_no]}"
        #@pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT 
        loss = true
        break
      end
      data_sub_n = data_req[:sub_no][0] 
      sub_buf[data_sub_n] = true
      sub_n += 1
      # Check Done
      if data_req[:extra] == "DONE"
        #puts "DATA DONE"
        for i in sub_n...CLI_ACK_SLICE_PKT
          sub_buf[i] = true
        end
        done = true
        break
      else
        #puts "Not DONE"
        done = false
      end
    end
    # 檢查sub buf 
    if sub_buf.all? {|v| v } && ( SERVER_LOSS_RATE == 0.0 || rand > SERVER_LOSS_RATE )
      # 全都有
    else
      loss = true
    end
    if RATE_BASED_WAIT_FOR_ACK
      # read ack
      # read until an ack appear
      #first = true
      begin
        #@pkt_buf.total_rx[@port] -= PACKET_SIZE if !first
        #first = false
        if got_ack_req
          data_ack_req = got_ack_req
          got_ack_req = nil
        else
          msg = pkt_handler.recv(PACKET_SIZE)
          timing = Timing.start
          data_ack_req = parse_command(msg)
          current_read += PACKET_SIZE
        end
        #puts "ACK：收到：#{data_ack_req}"
      end while !(data_ack_req[:is_request] && data_ack_req[:type] == "send ack")
      # ACK traffic count
      unless !got_ack_req && !TRAFFIC_COUNT_ACK
        $total_rx[port] += PACKET_SIZE
      end
      current_read -= PACKET_SIZE
      # send ack back
      req_to_reply(data_ack_req)
      if loss
        $total_rx_loss[port] += CLI_ACK_SLICE_PKT 
        data_ack_req[:extra] = "LOSS"
      else
        $total_rx[port] += current_read
        data_ack_req[:extra] = "OK"
        task_n += 1
        ack_cnt -= 1
      end
      io_time = get_disk_io_time(io_type)
      #printf "IO Time: %7.5f\n",io_time
      sleep io_time
      pkt_handler.send(pack_command(data_ack_req),0)
      #printf "ACK RTT: %9.4f ms\n",timing.end
      if TRAFFIC_COUNT_ACK
        $total_tx[port] += sz
      end
    else
      $total_rx[port] += current_read
      task_n += 1
    end
    if !loss && done
      #puts "DONE"
      break
    end
  end

end
def run_send_loop(pkt_handler,req)

end

def run_port_thread(port)
  thr = Thread.new do 
    sock = UDPSocket.new
    sock.bind($host_ip,port)
    loop do
      # receive command
      receiver = ReceiverProcess.bind_sock(sock,PASSIVE_PORT_TO_IP[port],port)
      cmd = receiver.recv(PACKET_SIZE)
      if TRAFFIC_COUNT_ACK
        $total_rx[port] += PACKET_SIZE
      end
      req = parse_command(cmd)
      if req[:is_request] && req[:type] == "send init"
        #while true
          #msg = receiver.recv(PACKET_SIZE)
          #$total_rx[port] += PACKET_SIZE
        #end
        run_recv_loop(receiver,req)
      elsif req[:is_request] && req[:type] == "recv init"
        sender = SenderProcess.bind_sock(sock,PASSIVE_PORT_TO_IP[port],port)
        run_send_loop(sender,req)
      end
    end
  end
end

pipe_r,pipe_w = IO.pipe

if pid = fork
  loop do
    data = []
    SERVER_OPEN_PORT_RANGE.each do 
      data << pipe_r.gets
    end
    data << pipe_r.gets

    clear_screen
    data.each do |str|
      print str
    end
  end
else
  pipe_r.close
  $stdout.reopen pipe_w
  
  # ///////////
  # setup recorder
  # ///////////
  $total_tx = {}
  $total_tx_loss = {}
  $total_rx = {}
  $total_rx_loss = {}
  $io_types = {}
  # ///////////
  # per-port loop
  # ///////////
  thr_port = []
  (SERVER_OPEN_PORT_RANGE).each do |port|
    $total_tx[port] = 0
    $total_tx_loss[port] = 0
    $total_rx[port] = 0
    $total_rx_loss[port] = 0
    thr_port << run_port_thread(port)
  end
  # ///////////
  # main:show info
  # ///////////
  last_rx_size = {}
  last_tx_size = {}
  (SERVER_OPEN_PORT_RANGE).each do |port|
    last_rx_size[port] = 0
    last_tx_size[port] = 0
  end
  last_time = Time.at(0)
  texts = []
  total_rx_diff = 0
  total_tx_diff = 0
  begin
    interval = IntervalWait.new
    loop do
      interval.sleep STATISTIC_INTERVAL
      total_rx_diff = 0
      total_tx_diff = 0
      texts = []
      (SERVER_OPEN_PORT_RANGE).each do |port|
        # RX
        cur_rx = $total_rx[port]
        rx_diff = cur_rx - last_rx_size[port]
        total_rx_diff += rx_diff
        last_rx_size[port] = cur_rx
        rx_loss = $total_rx_loss[port]
        if cur_rx > 0
          rx_loss_rate = rx_loss * PACKET_SIZE * 100.0 / (cur_rx + rx_loss * PACKET_SIZE)
        else
          rx_loss_rate = 0.0
        end

        # TX
        cur_tx = $total_tx[port]
        tx_diff = cur_tx - last_tx_size[port]
        total_tx_diff += tx_diff
        last_tx_size[port] = cur_tx
        tx_loss = $total_tx_loss[port]
        if cur_tx > 0
          tx_loss_rate = tx_loss * PACKET_SIZE * 100.0 / (cur_tx + tx_loss * PACKET_SIZE)
        else
          tx_loss_rate = 0.0
        end

        text = "#{port}:#{IO_TYPE_NAME[$io_types[port]]}:"
        text += sprintf("[RX]總:%11.3f Mbit，",cur_rx * 8.0 / UNIT_MEGA)
        text += "區:#{(sprintf("%8.3f",rx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL))} Mbit，遺失:#{sprintf(" %8.4f%%",rx_loss_rate)} "
        text += sprintf("[TX]總:%11.3f Mbit，",cur_tx * 8.0 / UNIT_MEGA)
        text += "區:#{(sprintf("%8.3f",tx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL))} Mbit，遺失:#{sprintf(" %8.4f%%",tx_loss_rate)} "
        texts << text
      end
      printf("===Spd:[RX] %8.3f Mbit [TX] %8.3f Mbit \n",total_rx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL,total_tx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL)
      final = ""
      texts.each do |text|
        final += text+"\n"
      end
      print final
    end
  rescue SystemExit, Interrupt
    puts "server結束"
  end
end














