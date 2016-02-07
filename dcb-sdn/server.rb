#!/usr/bin/env ruby 

require_relative 'config'


require 'socket'
require 'thread'
require 'qos-lib'
require 'packet_buffer'
require 'packet_handler'
require 'control_api'

STATISTIC_INTERVAL = 1


SERVER_OPEN_PORT_RANGE = 5001..5008
#SERVER_OPEN_PORT_RANGE = 5005..5005
#SERVER_OPEN_PORT_RANGE = 5002..5002
#SERVER_OPEN_PORT_RANGE = 5008..5008
#SERVER_OPEN_PORT_RANGE = 5005..5008

# Open files
$f_total = File.open("log/total","w")
$f_client = {}
SERVER_OPEN_PORT_RANGE.each do |port|
  $f_client[port] = File.open("log/client_#{port}","w")
end

if SERVER_RANDOM_FIXED_SEED
  srand(0)
end

$host_ip = ARGV[1]
if !$host_ip
  puts "Host IP required"
  exit
end


def run_port_thread(port)
  thr = Thread.new do 
    receiver = PassivePacketHandler.new($pkt_buf,PASSIVE_PORT_TO_IP[port],port)
    $control_api.register_handler(receiver)
    receiver.run_loop
  end
end

def run_read_thread
  thr = Thread.new do
    $pkt_buf.run_receive_loop
  end
end
def run_control_thread
  thr = Thread.new do
    $control_api.run_main_loop
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
  
  $pkt_buf = PacketBuffer.new($host_ip,$host_ip,SERVER_OPEN_PORT_RANGE)

  holder_list = TARGET_HOSTS_ID[$host_ip].join(',') # who will you send?
  $control_api = ControlAPI.new($host_ip,$host_ip,holder_list)
  $pkt_buf.register_control_api($control_api)
 
  # ///////////
  # Control Loop
  # ///////////
  thr_control = run_control_thread


  # ///////////
  # Pkt Buffer: stop_go_check
  # ///////////
  thr_stop_go_loop = Thread.new do
    $pkt_buf.stop_go_check_loop
  end

  # ///////////
  # Pkt Buffer: writer loop (for premature acks)
  # ///////////
  thr_write = []
  (SERVER_OPEN_PORT_RANGE).each do |port|
    thr_write << Thread.new do
      $pkt_buf.writer_loop(port)
    end
  end

  # ///////////
  # Pkt Buffer: read loop
  # ///////////
  thr_read = run_read_thread
  
  # ///////////
  # Pkt Handler: per-port loop
  # ///////////
  thr_port = []
  (SERVER_OPEN_PORT_RANGE).each do |port|
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
    loop do
      now = Time.now
      now_float = now.to_f
      if now - last_time > STATISTIC_INTERVAL
        total_rx_diff = 0
        total_tx_diff = 0
        texts = []
        last_time = Time.now
        (SERVER_OPEN_PORT_RANGE).each do |port|
          # RX
          cur_rx = $pkt_buf.total_rx[port]
          rx_diff = cur_rx - last_rx_size[port]
          total_rx_diff += rx_diff
          last_rx_size[port] = cur_rx
          rx_loss = $pkt_buf.total_rx_loss[port]
          if cur_rx > 0
            rx_loss_rate = rx_loss * PACKET_SIZE * 100.0 / (cur_rx + rx_loss * PACKET_SIZE)
          else
            rx_loss_rate = 0.0
          end
          rx_spd = rx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL
  
          # TX
          cur_tx = $pkt_buf.total_tx[port]
          tx_diff = cur_tx - last_tx_size[port]
          total_tx_diff += tx_diff
          last_tx_size[port] = cur_tx
          tx_loss = $pkt_buf.total_tx_loss[port]
          if cur_tx > 0
            tx_loss_rate = tx_loss * PACKET_SIZE * 100.0 / (cur_tx + tx_loss * PACKET_SIZE)
          else
            tx_loss_rate = 0.0
          end
          tx_spd = tx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL

          text = "#{port}:"
          text += sprintf("[RX]總:%11.3f Mbit，",cur_rx * 8.0 / UNIT_MEGA)
          text += "區:#{(sprintf("%8.3f",rx_spd))} Mbit，遺失:#{sprintf(" %8.4f%%",rx_loss_rate)} "
          text += sprintf("[TX]總:%11.3f Mbit，",cur_tx * 8.0 / UNIT_MEGA)
          text += "區:#{(sprintf("%8.3f",tx_spd))} Mbit，遺失:#{sprintf(" %8.4f%%",tx_loss_rate)} "
          texts << text

          $f_client[port].puts "#{now_float} #{rx_spd}"
        end
      end
      current_q = DCB_SERVER_BUFFER_PKT_SIZE - $pkt_buf.available
      q_rate = (current_q * 100.0)/DCB_SERVER_BUFFER_PKT_SIZE
      total_tx_spd = total_tx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL
      total_rx_spd = total_rx_diff * 8.0 / UNIT_MEGA / STATISTIC_INTERVAL
      $f_total.puts "#{now_float} #{total_rx_spd}"
      printf("===Spd:[RX] %8.3f Mbit [TX] %8.3f Mbit ; Q: %5d(%5.2f%%) :#{'|'*(0.25*q_rate).ceil}\n",total_rx_spd,total_tx_spd,current_q,q_rate)
      final = ''
      texts.each do |text|
        final += text+"\n"
      end
      print final
      sleep [STATISTIC_INTERVAL / 2.0,0.1].max
    end
  rescue SystemExit, Interrupt
    puts "server結束"
  end


end














