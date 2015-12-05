class PacketHandler
  def initialize(pkt_buf,port)
    @pkt_buf = pkt_buf
    @block_buf = []
    @port = port
    @wait_for_packet = false
    @recv_buff = [false]*CLI_ACK_SLICE_PKT
    @recv_count = 0
    @task_cnt = 0
  end

  def run_loop
    n = 0
    loop do
      n+= 1
      #puts n
      #execute_buffer
      pkt = extract_next_packet
      if pkt
        process_packet(pkt)
      elsif !@wait_for_packet
        execute_next_action
      end
    end
  end

  def execute_buffer
    block_buf = @pkt_buf.extract_block(@port)
    block_buf.each do |pkt|
      process_packet(pkt)
    end
  end

  def extract_next_packet(timeout = nil)
    # process data in block
    if @block_buf.empty?
      @block_buf = @pkt_buf.extract_block(@port,timeout)
      if !@block_buf.empty?
        #puts "#{@port} Extracted block#: #{@block_buf.size}"
        #sleep (rand(3)+1)*0.0001
      else
        #sleep 0.1
      end
    end
    if !@block_buf.empty?
      #puts "buffer remain:#{@block_buf.size}"
      return @block_buf.shift
    else
      return nil
    end
  end

  def execute_next_action
    return nil
  end

  def process_data_packet(pkt)
    task_n = pkt[:req][:task_no]
    if task_n != @task_cnt
      #puts "錯誤的大編號：#{task_n}，預期：#{@task_cnt}"
      CLI_ACK_SLICE_PKT.times do |i|
        @recv_buff[i] = false
      end
      @pkt_buf.total_rx_loss[@port] += (CLI_ACK_SLICE_PKT - @recv_count  + CLI_ACK_SLICE_PKT * (task_n - @task_cnt - 1))
      @recv_count = 0
      @task_cnt = task_n
      $pkt_buf.disk_lock.unlock if $pkt_buf.disk_lock.owned? && $pkt_buf.disk_lock.locked?
    end
    sub_n = pkt[:req][:sub_no][0]
    #print "收到編號：#{sub_n}，"
    if @recv_buff[sub_n]
      # exist
      #puts "重複封包：#{sub_n}"
    else
      # not exist
      #puts "正確編號：#{sub_n}"
      @recv_buff[sub_n] = true
      @recv_count += 1

      if sub_n == 0
        $pkt_buf.disk_lock.lock
      end
      # full?
      if @recv_count == CLI_ACK_SLICE_PKT
        # full
        CLI_ACK_SLICE_PKT.times do |i|
          @recv_buff[i] = false
        end
        @recv_count = 0
        # IO 
        sleep 0.02
        $pkt_buf.disk_lock.unlock if $pkt_buf.disk_lock.owned? && $pkt_buf.disk_lock.locked?
        @task_cnt += 1
      else
        # not full
      end
    end
  end

  def process_ack_request(pkt)
    #puts "處理ACK request，給：#{pkt[:peer]}"
    req = pkt[:req]
    req[:is_request] = false
    req[:is_reply] = true
    if $pkt_buf.disk_lock.owned? && $pkt_buf.disk_lock.locked?
      $pkt_buf.disk_lock.unlock
    end
    #$pkt_buf.disk_lock.synchronize do
      #sleep 1
    #end
    write_packet_req(req,*(pkt[:peer]))
  end

  def process_packet(pkt)
    #puts pkt[:msg]
    case pkt[:req][:type]
    when "data send"
      process_data_packet(pkt)
    when "data ack"
      process_ack_request(pkt)
    end
  end

  def write_packet_req(req,*peer)
    @pkt_buf.write_packet_req(@port,req,*peer)
  end

end

class PassivePacketHandler < PacketHandler
  def initialize(pkt_buf,port)
    super(pkt_buf,port)
    pkt_buf.send_go
  end
end

class ActivePacketHandler < PacketHandler
  def initialize(pkt_buf,port)
    super(pkt_buf,port)
  end

  # DEBUG
  def run_loop
    i = 0
    loop do
      #(rand(5)+1).times do
        while !@pkt_buf.send_ok
          sleep 0.0001
        end
        CLI_ACK_SLICE_PKT.times do |j|
          req = {}
          req[:is_request] = true
          req[:type] = "data send"
          req[:task_no] = i
          req[:sub_no] = [j]
          write_packet_req(req)
        end
        send_and_wait_for_ack
        #sleep 0.02
        i += 1
      #end
      #sleep rand(1)+rand
    end
  end
  
  def write_ack_req
    req = {}
    req[:is_request] = true
    req[:type] = "data ack"
    #puts "傳輸資料ACK"
    write_packet_req(req)
  end

  def send_and_wait_for_ack
    write_ack_req
    loop do
      # get next
      pkt = extract_next_packet(1)
      if pkt && pkt[:req][:type] == "data ack"
        #puts "收到ACK reply"
        break
      else
        # Timedout
        puts "重新傳輸ACK request"
        write_ack_req

      end
    end
  end

  def execute_next_action

  end
end

