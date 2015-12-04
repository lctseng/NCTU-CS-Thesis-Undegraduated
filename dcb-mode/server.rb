#!/usr/bin/env ruby 

require_relative 'config'


require 'socket'
require 'thread'
require 'qos-lib'
require 'packet_buffer'
require 'signal_sender'
require 'packet_handler'


#SERVER_OPEN_PORT_RANGE = 5002..5008
#SERVER_OPEN_PORT_RANGE = 5005..5005
#SERVER_OPEN_PORT_RANGE = 5002..5002
#SERVER_OPEN_PORT_RANGE = 5008..5008
SERVER_OPEN_PORT_RANGE = 5005..5008

if SERVER_RANDOM_FIXED_SEED
  srand(0)
end


def run_port_thread(port)
  thr = Thread.new do 
    receiver = PassivePacketHandler.new($pkt_buf,port)
    receiver.run_loop
  end
end

def run_port_read_thread(port)
  thr = Thread.new do
    $pkt_buf.run_port_receive_loop(port)
  end
end
def run_read_thread
  thr = Thread.new do
    $pkt_buf.run_receive_loop
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
    data.each do |str|
      puts str
    end
  end
else
  pipe_r.close
  $stdout.reopen pipe_w
  $signal_sender.bind_port
  $pkt_buf = PacketBuffer.new("0.0.0.0",SERVER_OPEN_PORT_RANGE)
  $pkt_buf.notifier = $signal_sender
  $signal_sender.pkt_buf = $pkt_buf
  thr_accept = run_accept_thread
  
  #thr_read = []
  #(SERVER_OPEN_PORT_RANGE).each do |port|
  #  thr_read << run_port_read_thread(port)
  #end
  thr_read = run_read_thread
  
  thr_port = []
  (SERVER_OPEN_PORT_RANGE).each do |port|
    thr_port << run_port_thread(port)
  end
  # main:show info
  last_rx_size = {}
  last_tx_size = {}
  (SERVER_OPEN_PORT_RANGE).each do |port|
    last_rx_size[port] = 0
    last_tx_size[port] = 0
  end
  last_time = Time.at(0)
  texts = []
  begin
    loop do
      if Time.now - last_time > 1
        texts = []
        last_time = Time.now
        (SERVER_OPEN_PORT_RANGE).each do |port|
          cur_rx = $pkt_buf.total_rx[port]
          rx_diff = cur_rx - last_rx_size[port]
          last_rx_size[port] = cur_rx


          cur_tx = $pkt_buf.total_tx[port]
          tx_diff = cur_tx - last_tx_size[port]
          last_tx_size[port] = cur_tx

          rx_loss = $pkt_buf.total_rx_loss[port]
          if cur_rx > 0
            rx_loss_rate = rx_loss * PACKET_SIZE * 100.0 / cur_rx
          else
            rx_loss_rate = 0.0
          end

          text = "#{port}:"
          text += sprintf("[RX]總:%11.3f Mbit，",cur_rx * 8.0 / UNIT_MEGA)
          text += "區:#{(sprintf("%8.3f",rx_diff * 8.0 / UNIT_MEGA))} Mbit，遺失:#{sprintf("%6dp (%6.4f%%)",rx_loss,rx_loss_rate)} "
          text += sprintf("[TX]總:%11.3f Mbit，",cur_tx * 8.0 / UNIT_MEGA)
          text += "區:#{(sprintf("%8.3f",tx_diff * 8.0 / UNIT_MEGA))} Mbit，遺失:#{sprintf('%6d',$pkt_buf.total_tx_loss[port])}p "
          texts << text
        end
      end
      current_q = DCB_SERVER_BUFFER_PKT_SIZE - $pkt_buf.available
      q_rate = (current_q * 100.0)/DCB_SERVER_BUFFER_PKT_SIZE
      printf("=====Q: %5d(%5.2f%%) :#{'|'*(0.7*q_rate).ceil}\n",current_q,q_rate)
      texts.each do |text|
        print text+"\n"
      end
      sleep 0.1
    end
  rescue SystemExit, Interrupt
    puts "server結束"
  end


end














