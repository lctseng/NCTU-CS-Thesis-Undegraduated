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
      sleep 0.001
      execute_buffer
      #pkt = extract_next_packet
      #if pkt
      #  process_packet(pkt)
      #elsif !@wait_for_packet
      #  execute_next_action
      #end
    end
  end

  def execute_buffer
    block_buf = @pkt_buf.extract_block(@port)
    block_buf.each do |pkt|
      process_packet(pkt)
    end
  end

  def extract_next_packet
    # process data in block
    if @block_buf.empty?
      @block_buf = @pkt_buf.extract_block(@port)
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

  def process_packet(pkt)
    task_n = pkt[:req][:task_no]
    if task_n != @task_cnt
      puts "錯誤的大編號：#{task_n}，預期：#{@task_cnt}"
      CLI_ACK_SLICE_PKT.times do |i|
        @recv_buff[i] = false
      end
      @pkt_buf.total_rx_loss[@port] += (CLI_ACK_SLICE_PKT - @recv_count  + CLI_ACK_SLICE_PKT * (task_n - @task_cnt - 1))
      @recv_count = 0
      @task_cnt = task_n
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
      # full?
      if @recv_count == CLI_ACK_SLICE_PKT
        # full
        CLI_ACK_SLICE_PKT.times do |i|
          @recv_buff[i] = false
        end
        @recv_count = 0
        # IO 
        #$pkt_buf.disk_lock.synchronize do
          #sleep 0.1
        #end
        @task_cnt += 1
      else
        # not full
      end
    end
  end

  def write_packet_req(req)
    @pkt_buf.write_packet_req(@port,req)
  end

end

class PassivePacketHandler < PacketHandler
  def initialize(pkt_buf,port)
    super(pkt_buf,port)
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
      CLI_ACK_SLICE_PKT.times do |j|
        req = {}
        req[:is_request] = true
        req[:task_no] = i
        req[:sub_no] = [j]
        write_packet_req(req)
      end
      sleep 0.2
      i += 1
    end
  end
  def execute_next_action

  end
end

