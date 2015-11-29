#!/usr/bin/env ruby 


require 'socket'
require_relative 'qos-info'
require_relative 'qos-lib'

$DEBUG = true


port = ARGV[0].to_i
use_sock = ARGV[1] =~ /-s/


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


case DATA_PROTOCOL
when :tcp
  server = TCPServer.new("0.0.0.0",port)
  $output.puts "等待TCP port：#{port}"
  receiver = server.accept
when :udp
  receiver = UDPSocket.new
  receiver.bind("0.0.0.0",port)
end


def send_request_confirm(receiver,req)
  case req[:type]
  when "send_request"
    req[:type] = "send_confirm"
  else
    req[:type] = "noop"
  end
  req[:is_request] = false
  req[:is_reply] = true

  if DATA_PROTOCOL == :udp
    #$output.puts "傳送要求給#{$addr}"
    receiver.send(pack_command(req),0,$addr[3],$addr[1])
  else
    receiver.send(pack_command(req),0)
  end
end

def send_ack_confirm(receiver,req)
  case req[:type]
  when "send_ack"
    req[:type] = "send_ack"
  else
    req[:type] = "noop"
  end
  req[:is_request] = false
  req[:is_reply] = true

  # TODO: timing
  spin_time (rand(11)+5)*0.001
  if DATA_PROTOCOL == :udp
    #$output.puts "傳送ACK給#{$addr}"
    receiver.send(pack_command(req),0,$addr[3],$addr[1])
  else
    receiver.send(pack_command(req),0)
  end
end

def send_recv_request_confirm(receiver,req)
  case req[:type]
  when "recv_request"
    req[:type] = "recv_confirm"
  else
    req[:type] = "noop"
  end
  req[:is_request] = false
  req[:is_reply] = true
  if DATA_PROTOCOL == :udp
    receiver.send(pack_command(req),0,$addr[3],$addr[1])
  else
    receiver.send(pack_command(req),0)
  end

end

# 廢棄
def send_recv_pkt_ack_request(receiver,o_req)
  req = {}
  req[:is_request] = true
  req[:type] = "recv_pkt_ack"
  req[:data_size] = o_req[:data_size]
  if DATA_PROTOCOL == :udp
    receiver.send(pack_command(req),0,$addr[3],$addr[1])
  else
    receiver.send(pack_command(req),0)
  end
end

def send_recv_pkt_data(receiver,o_req,index)
  req = {}
  req[:is_reply] = true
  req[:type] = "recv_pkt_reply"
  req[:task_no] = index
  req[:data_size] = o_req[:data_size]
  if DATA_PROTOCOL == :udp
    return receiver.send(pack_command(req),0,$addr[3],$addr[1])
  else
    return receiver.send(pack_command(req),0)
  end
end

def reset_variables
  $cnt = 0
  $loss = 0
  $size_total = 0.0
  $last_size = 0.0
  $loss_cnt = {}
  $state = :wait # wait , receive, send
  $task_no = 0
  $sub_count = 0
  $size_to_receive = 0
  $data_size_lost = 0
  $total_send = 0
  $last_tota_send = 0
  $send_loss = 0
end

reset_variables

Thread.new do 
  loop do
    r_diff = $size_total - $last_size
    $last_size = $size_total
    w_diff = $total_send - $last_tota_send
    $last_tota_send = $total_send
    $output.printf("[RX]總:%11.3f Mbit，",$size_total * 8.0 / UNIT_MEGA)
    $output.print "區:#{(sprintf("%8.3f",r_diff * 8.0 / UNIT_MEGA))} Mbit，遺失:#{sprintf('%4d',$loss)}p "
    $output.printf("[TX]總:%11.3f Mbit，",$total_send * 8.0 / UNIT_MEGA)
    $output.puts "區:#{(sprintf("%8.3f",w_diff * 8.0 / UNIT_MEGA))} Mbit，遺失:#{sprintf('%4d',$send_loss)}p"
    sleep 1
  end
end




begin
  loop do
    # 主迴圈，處理需求
    if DATA_PROTOCOL == :udp
      str,$addr = receiver.recvfrom(PACKET_SIZE)
    else
      str = receiver.read(PACKET_SIZE)
    end
    req = parse_command(str)
    size_plus = false
    #puts "大小：#{str.size}，收到：#{str}"
    if req[:type] == "reset"
      reset_variables
      next
    elsif req[:is_request]
      # 檢查是不是新要求，若是，試圖進入狀態(若已進入則忽略)
      case req[:type]
      when "send_request"
        case $state
        when :wait
          # 新的request
          #$output.puts "收到新的send request：#{req[:task_no]}"
          $task_no = req[:task_no]
          $sub_count = 1
          $size_to_receive = 0
          $state = :receive
          $current_data_lost = 0
          send_request_confirm(receiver,req)
        when :receive
          if req[:task_no] <= $task_no
            # 重複request，忽略
            $output.puts "收到重複的send request:#{req[:task_no]}，當前task_no = #{$task_no}"
            send_request_confirm(receiver,req)
          else
            # 新的sending request，舊的資料可能遺失
            $output.puts "強迫開始傳輸#{req[:task_no]}，遺失#{$task_no}以前的資料共#{$size_to_receive}bytes"
            $data_size_lost += $size_to_receive
            $current_data_lost = $size_to_receive
            $task_no = req[:task_no]
            $sub_count = 1
            $size_to_receive = 0
            $state = :receive
            $current_data_lost = 0
            send_request_confirm(receiver,req)
          end
        when :send
          # FIXME:暫不考慮
        end
      when "send"
        case $state
        when :receive
          # 開始收資料
          if $task_no < req[:task_no]
            # 收到未來的資料！
            $output.puts "收到未來的task_no！預期task_no = #{$task_no}，收到：#{req[:task_no]}"
          elsif $task_no == req[:task_no]
            # 檢查sub_no
            first_no = req[:sub_no][0]
            if first_no == $sub_count
              # 正常
              $sub_count += 1
              size_plus = true
              $size_to_receive = req[:data_size]
            elsif first_no > $sub_count
              #diff = $size_to_receive - req[:data_size] + PACKET_SIZE
              #puts "task #{$task_no} 遺失資料！遺失#{$sub_count}到#{first_no}的資料共#{diff}bytes" 
              #$output.puts "task #{$task_no} 遺失資料！遺失#{$sub_count}到#{first_no}的封包"
              $size_to_receive = req[:data_size]
              # 有資料遺失
              new_loss = $loss + (first_no - $sub_count)
              #$output.puts "封包遺失從#{$loss}增加為#{new_loss}"
              $loss = new_loss
              for cnt in $sub_count...first_no
                $loss_cnt[cnt] = true
              end
              $sub_count = first_no + 1
              size_plus = true
            else
              if $loss_cnt.has_key? first_no
                $loss -= 1
                #$output.puts "錯位封包：#{first_no}"
                $loss_cnt.delete first_no
              end
              # 重複資料
            end
            if size_plus && $state == :receive
              #puts "剩餘大小：#{req[:data_size]}"
              if req[:data_size] <= 0
                # 結束接收
                #puts "結束#{$task_no}的資料接收，總共遺失資料：#{$current_data_lost}bytes"
                #$output.puts "結束#{$task_no}的資料接收"
                $task_no = 0
                $state = :wait
              end
            end
          else
            # 收到舊的資料！
            $output.puts "收到舊的的task_no！預期task_no = #{$task_no}，收到：#{req[:task_no]}"
          end
        else # else case state

        end
      when "send_ack" # 傳送的ACK
        # ACK的task no少1
        send_ack_confirm(receiver,req)
      when "recv_request"
        # 等等要送資料
        $state = :send
        #puts "已收到recv request for #{req[:data_size]}"
        send_recv_request_confirm(receiver,req)
      when "recv_pkt_request"
        spin_time (rand(11)+5)*0.001
        # 開始送一連續的封包
        if rand >= 0.0
          req[:data_size].times do |i|
            $total_send += send_recv_pkt_data(receiver,req,i)
          end
          #$output.puts "已傳送#{req[:data_size]}個封包"
        end
        # 等client的ack 
        str = receiver.read(PACKET_SIZE)
        ack_req = parse_command(str)
        if ack_req[:is_request] && ack_req[:type] == "recv_pkt_ack"
          #$output.puts "已收到ACK，回傳"
          ack_req[:is_reply] = true
          ack_req[:is_request] = false
          if DATA_PROTOCOL == :udp
            receiver.send(pack_command(ack_req),0,$addr[3],$addr[1])
          else
            receiver.send(pack_command(ack_req),0)
          end
        else
          $output.puts "警告：收到非ack的封包"
        end
        
        $state = :wait
      else
        next
      end
    else
      # FIXME:忽略request以外的東西
      next
    end
    $size_total += str.size if size_plus
  end
rescue SystemExit, Interrupt
  $output.puts "receiver結束"
end
