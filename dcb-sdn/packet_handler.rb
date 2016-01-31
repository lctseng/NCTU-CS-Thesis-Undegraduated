require_relative 'common'
class PacketHandler

  attr_reader :id
  attr_reader :peer_ip
  attr_reader :port

  attr_reader :token
  attr_reader :lock_file
  attr_accessor :token_getter

  attr_reader :token_lock
  attr_reader :token_ready

  def initialize(pkt_buf,peer_ip,port)
    @pkt_buf = pkt_buf
    @peer_ip = peer_ip
    @port = port
    @id = "#{peer_ip}:#{port}"
    connection_data_reset
    @lock_file = File.open("lock_file/#{@pkt_buf.my_addr}.lock","w")
    @stop = false
    
    @token = 0
    @token_lock = Mutex.new
    @token_ready = ConditionVariable.new

  end
  
  def give_token(n,time)
    @token_lock.synchronize do
      @token += n
      @token_ready.signal
    end
    #printf "Token #{n} Got, Delay %7.3f ms\n",(Time.now.to_f - time)*1000
  end

  def ensure_token(min,max)
    max = [max,DCB_SDN_MAX_TOKEN_REQ].min
    max = min if max < min
    @token_lock.synchronize do
      while @token < min
        get_min = min - @token
        get_max = max - @token 
        get_token(get_min,get_max)
      end
    end
  end

  def get_token(min,max)
    call_time = Time.now
    @token_getter.get_token(self,min,max)
    printf("Token Delay: %7.3f ms\n",(Time.now - call_time)*1000) if @pkt_buf.active
  end

  def restore_token(n)
    @token_getter.restore_token(self,n)
  end


  def connection_data_reset
    @block_buf = []
    @wait_for_packet = false
    @recv_buff = [false]*CLI_ACK_SLICE_PKT
    @recv_count = 0
    @task_cnt = 0

  end

  def end_connection
    connection_data_reset
    @pkt_buf.end_connection(@port)
  end

  def run_loop
    raise RuntimeError,"No loop defined"
  end

  def execute_buffer
    block_buf = @pkt_buf.extract_block(@port)
    block_buf.each do |pkt|
      process_packet(pkt)
    end
  end

  def extract_next_packet(timeout = nil)
    # process data in block
    while @block_buf.empty?
      timing = Timing.start
      @block_buf = @pkt_buf.extract_block(@port,timeout)
      #puts "Block Extract Delay :#{timing.end} ms，Size：#{@block_buf.size}"
    end
    #puts "Buffer size: #{@block_buf.collect{|s| s.class}}"
    if !@block_buf.empty?
      #puts "buffer remain:#{@block_buf.size}"
      return @block_buf.shift
    else
      return nil
    end
  end

  def write_packet_req(req,*peer)
    @pkt_buf.write_packet_req(@port,req,*peer)
  end
  def write_packet_raw(str,*peer)
    @pkt_buf.write_packet_raw(@port,str,*peer)
  end

  def cleanup
    @lock_file.flock(File::LOCK_UN)
  end
  
  def send_and_wait_for_ack(ack_req,*peer)
    str = pack_command(ack_req)
    sz = write_packet_raw(str,*peer)
    # Restore writing size
    @pkt_buf.total_tx[@port] -= sz if !TRAFFIC_COUNT_ACK
    loop do
      # get next
      timing = Timing.start
      pkt = extract_next_packet(5)
      #puts "Extract delay: #{timing.end}ms"
      if pkt && pkt[:req][:is_reply] && pkt[:req][:type] == ack_req[:type]
        #puts "收到ACK reply"
        @pkt_buf.total_rx[@port] -= pkt[:size] if !TRAFFIC_COUNT_ACK
        return pkt[:req]
      else
        # Timedout
        puts "重新傳輸 #{ack_req[:type]} request"
        ensure_token(1,1)
        @token -= 1
        sz = write_packet_raw(str,*peer)
        # Restore writing size
        @pkt_buf.total_tx[@port] -= sz if !TRAFFIC_COUNT_ACK
      end
    end
  end

end

class PassivePacketHandler < PacketHandler
  def initialize(pkt_buf,peer_ip,port)
    super
  end
 
  def run_send_loop(pkt)
    # Write back ack right now
    ack_req = pkt[:req]
    peer = pkt[:peer]
    # Compute pkt count
    pkt_cnt = (ack_req[:data_size].to_f / PACKET_SIZE ).ceil
    # Reply Ack
    req_to_reply(ack_req)
    ensure_token(1,1)
    @token -= 1
    sz = write_packet_req(ack_req,*peer)
    if !TRAFFIC_COUNT_ACK
      @pkt_buf.total_tx[@port] -= sz
    end
    # Prepare
    i = 0
    done = false
    stop = false
    # ACK Req
    ack_req = {}
    ack_req[:is_request] = true
    ack_req[:type] = "recv ack"
    last_time = Time.now
    # Data Req
    data_req = {}
    data_req[:is_request] = true
    data_req[:type] = "recv data"
    loop do # send loop
      current_send = 0
      # start block
      send_min = [CLI_ACK_SLICE_PKT,pkt_cnt].min
      min = send_min + DCB_SDN_EXTRA_TOKEN_USED
      ensure_token(min,min)
      send_min.times do |j|
        data_req[:task_no] = i
        data_req[:sub_no] = [j]
        current_send += 1
        pkt_cnt -= 1
        current_send += 1
        if pkt_cnt <= 0
          data_req[:extra] = "DONE"
          done = true
        else
          data_req[:extra] = "CONTINUE"
        end
        write_packet_req(data_req,*peer)
      end
      @token -= send_min
      # send ack
      if DCB_SENDER_REQUIRE_ACK
        @token -= 1
        reply_req = send_and_wait_for_ack(ack_req,*peer)

        if reply_req[:extra] == "LOSS"
          pkt_cnt += current_send
          @pkt_buf.total_tx[@port] -= current_send * PACKET_SIZE
          @pkt_buf.total_tx_loss[@port] += CLI_ACK_SLICE_PKT 
          done = false
        else
          if done
            stop = true
          end
          i += 1
        end
      else
        if done
          stop = true
        end
        i += 1
      end
      if stop
        break
      end
    end

  end

  def run_recv_loop(pkt)
    # Write back ack right now
    ack_req = pkt[:req]
    # Compute loop number
    ack_cnt = (ack_req[:data_size].to_f / CLI_ACK_SLICE ).ceil
    # Reply Ack
    req_to_reply(ack_req)
    ensure_token(1,ack_cnt + 1)
    #ensure_token(1,1)
    @token -= 1
    sz = write_packet_req(ack_req,*pkt[:peer])
    if !TRAFFIC_COUNT_ACK
      @pkt_buf.total_tx[@port] -= sz
    end
    # Prepare
    task_n = 0
    done = false
    loop do # receive loop
      # read block
      got_ack_pkt = nil
      sub_n = 0
      loss = false
      current_read = 0
      
      # Sub data buffer
      sub_buf = [false] * CLI_ACK_SLICE_PKT
      timing = Timing.start
      while sub_n < CLI_ACK_SLICE_PKT
        data_pkt = extract_next_packet
        current_read += data_pkt[:size]
        data_req = data_pkt[:req]
        if data_req[:type] != "send data"
          if data_req[:type] == "send ack"
            #puts "提早收到ACK"
            got_ack_pkt = data_pkt
            #@pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT - 1 - sub_n
            loss = true
            break
          else
            puts "收到預期外封包" 
          end
        end
        if data_req[:task_no] != task_n
          #puts "Task預期：#{task_n}，收到：#{data_req[:task_no]}"
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
          done = false
        end
      end
      #puts "Timing : #{timing.end} ms"
      # 檢查sub buf  
      if sub_buf.all? {|v| v } && ( SERVER_LOSS_RATE == 0.0 || rand > SERVER_LOSS_RATE )
        # 全都有
      else
        loss = true
      end
      # read ack
      ack_timing = Timing.start
      # read until an ack appear
      #first = true
      begin
        #@pkt_buf.total_rx[@port] -= PACKET_SIZE if !first
        #first = false
        if got_ack_pkt
          data_ack_pkt = got_ack_pkt
          got_ack_pkt = nil
        else
          data_ack_pkt = extract_next_packet
          current_read += data_ack_pkt[:size]
        end
        data_ack_req = data_ack_pkt[:req]
        #puts "ACK：收到：#{data_ack_req}"
      end while !(data_ack_req[:is_request] && data_ack_req[:type] == "send ack")
      # ACK traffic count
      if !got_ack_pkt && !TRAFFIC_COUNT_ACK
        @pkt_buf.total_rx[@port] -= PACKET_SIZE
      end
      current_read -= PACKET_SIZE
      # send ack back
      req_to_reply(data_ack_req)
      if loss
        @pkt_buf.total_rx[@port] -= current_read
        @pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT 
        data_ack_req[:extra] = "LOSS"
      else
        data_ack_req[:extra] = "OK"
        task_n += 1
        ack_cnt -= 1
      end
      ensure_token(1,ack_cnt)
      #ensure_token(1,ack_cnt)
      @token -= 1
      write_packet_req(data_ack_req,*data_ack_pkt[:peer])
      #puts "ACK Timing:#{ack_timing.end}ms"
      if !TRAFFIC_COUNT_ACK
        @pkt_buf.total_tx[@port] -= sz
      end
      if !loss && done
        #puts "DONE"
        break
      end
    end
  end


  def run_loop
    loop do
      pkt = extract_next_packet
      if pkt
        if !TRAFFIC_COUNT_ACK
          @pkt_buf.total_rx[@port] -= pkt[:size]
        end
        if pkt[:req][:is_request] && pkt[:req][:type] == "send init"
          run_recv_loop(pkt)
        elsif pkt[:req][:is_request] && pkt[:req][:type] == "recv init"
          run_send_loop(pkt)
        end
      end
    end
  end
  
end

class ActivePacketHandler < PacketHandler


  def initialize(pkt_buf,peer_ip,port,total_send)
    super(pkt_buf,peer_ip,port)
    @stop = false
    @total_send = total_send
  end

  def run_loop(type)
    case type
    when "read"
      run_recv_loop
    when "write"
      run_send_loop
    end
  end

  def run_recv_loop
    ack_cnt = (@total_send.to_f / CLI_ACK_SLICE ).ceil
    # Send Init request
    init_req = {}
    init_req[:is_request] = true
    init_req[:type] = "recv init"
    init_req[:data_size] = @total_send
    ensure_token(1,1)
    send_and_wait_for_ack(init_req)
    task_n = 0
    # Recv loop
    loop do
      # read block
      got_ack_pkt = nil
      sub_n = 0
      loss = false
      current_read = 0

      # Sub data buffer
      sub_buf = [false] * CLI_ACK_SLICE_PKT

      while sub_n < CLI_ACK_SLICE_PKT
        data_pkt = extract_next_packet
        current_read += data_pkt[:size]
        data_req = data_pkt[:req]
        if data_req[:type] != "recv data"
          if data_req[:type] == "recv ack"
            #puts "提早收到ACK"
            got_ack_pkt = data_pkt
            #@pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT - 1 - sub_n
            loss = true
            break
          else
            puts data_req
            puts "收到預期外封包" 
          end
        end
        if data_req[:task_no] != task_n
          #puts "Task預期：#{task_n}，收到：#{data_req[:task_no]}"
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
          done = false
        end
      end
      # 檢查sub buf 
      if sub_buf.all? {|v| v } && ( CLIENT_LOSS_RATE == 0.0 || rand > CLIENT_LOSS_RATE )
        # 全都有
      else
        loss = true
      end
      # read ack
      # read until an ack appear
      begin
        if got_ack_pkt
          data_ack_pkt = got_ack_pkt
          got_ack_pkt = nil
        else
          data_ack_pkt = extract_next_packet
          current_read += data_ack_pkt[:size]
        end
        data_ack_req = data_ack_pkt[:req]
        #puts "ACK：收到：#{data_ack_req}"
      end while !(data_ack_req[:is_request] && data_ack_req[:type] == "recv ack")
      # ACK traffic count
      if !got_ack_pkt && !TRAFFIC_COUNT_ACK
        @pkt_buf.total_rx[@port] -= PACKET_SIZE
      end
      current_read -= PACKET_SIZE
      # send ack back
      req_to_reply(data_ack_req)
      if loss
        data_ack_req[:extra] = "LOSS"
      else
        data_ack_req[:extra] = "OK"
        task_n += 1
        ack_cnt -= 1
      end
      ensure_token(1,ack_cnt)
      #ensure_token(1,ack_cnt)
      @token -= 1
      #puts "Reply ACK：#{data_ack_req}"
      write_packet_req(data_ack_req)
      if !loss && done
        puts "DONE"
        Process.kill("INT",Process.pid)
        break
      end


    end

  end

  def run_send_loop
    i = 0
    ack_req = {}
    ack_req[:is_request] = true
    ack_req[:type] = "send ack"
    timing = Timing.start
    # Data Req
    data_req = {}
    data_req[:is_request] = true
    data_req[:type] = "send data"
    # Send Init request
    init_req = {}
    init_req[:is_request] = true
    init_req[:type] = "send init"
    init_req[:data_size] = @total_send
    ensure_token(1,1)
    send_and_wait_for_ack(init_req)
    @token -= 1
    # Start Data Packet
    loop do
      current_send = 0
      #puts "Start #{i} , interval = #{timing.end}ms"
      #(rand(100)+1).times do
      done = false
      min = CLI_ACK_SLICE_PKT +  DCB_SDN_EXTRA_TOKEN_USED
      ensure_token(min,min)
      CLI_ACK_SLICE_PKT.times do |j|
        data_req[:task_no] = i
        data_req[:sub_no] = [j]
        @total_send -= PACKET_SIZE
        current_send += PACKET_SIZE
        if @total_send <= 0
          data_req[:extra] = "DONE"
          done = true
        else
          data_req[:extra] = "CONTINUE"
        end
        write_packet_req(data_req)
        if done
          #puts "pre-DONE"
          @token += CLI_ACK_SLICE_PKT - 1 - j
          break
        end
      end
      @token -= CLI_ACK_SLICE_PKT 
      if DCB_SENDER_REQUIRE_ACK
        @token -= 1
        ack_timing = Timing.start
        reply_req = send_and_wait_for_ack(ack_req)
        #puts "ACK delay: #{ack_timing.end} ms"
        if reply_req[:extra] == "LOSS"
          @total_send += current_send
          done = false
        else
          if done
            @stop = true
          end
          i += 1
        end
      else
        if done
          @stop = true
        end
        i += 1
      end
      if @stop
        restore_token(@token)
        cleanup
        Process.kill("INT",Process.pid)
        break
      end
    end
  end

  

  def execute_next_action
  end

  def cleanup
    super
  end
end

