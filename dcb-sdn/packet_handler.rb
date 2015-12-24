class PacketHandler

  attr_reader :id
  attr_reader :peer_ip
  attr_reader :port

  attr_reader :token
  attr_reader :lock_file
  attr_accessor :token_getter

  attr_reader :token_lock
  attr_reader :token_ready

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
    printf("Token Delay: %7.3f ms\n",(Time.now - call_time)*1000)
  end

  def restore_token(n)
    @token_getter.restore_token(self,n)
  end

  #
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
    n = 0
    loop do
      n+= 1
      #puts n
      #execute_buffer
      pkt = extract_next_packet
      if pkt
        process_packet(pkt)
        if @stop
          break
        end
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
      loss = (CLI_ACK_SLICE_PKT - @recv_count  + CLI_ACK_SLICE_PKT * (task_n - @task_cnt - 1))
      @pkt_buf.total_rx_loss[@port] += loss
      @pkt_buf.add_free_token(loss)
      @recv_count = 0
      @task_cnt = task_n
      @lock_file.flock(File::LOCK_UN)
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
        @lock_file.flock(File::LOCK_EX)
      end
      # full?
      if @recv_count == CLI_ACK_SLICE_PKT
        # full
        CLI_ACK_SLICE_PKT.times do |i|
          @recv_buff[i] = false
        end
        @recv_count = 0
        # IO 
        sleep get_disk_io_time
        @lock_file.flock(File::LOCK_UN)
        if DCB_CEHCK_MAJOR_NUMBER
          @task_cnt += 1
        end
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
    @lock_file.flock(File::LOCK_UN)
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
    when "end connection"
      end_connection
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
  
  def send_and_wait_for_ack(ack_req)
    str = pack_command(ack_req)
    write_packet_raw(str)
    loop do
      # get next
      pkt = extract_next_packet(5)
      if pkt && pkt[:req][:is_reply] && pkt[:req][:type] == ack_req[:type]
        #puts "收到ACK reply"
        return pkt[:req]
      else
        # Timedout
        puts "重新傳輸 #{ack_req[:type]} request"
        ensure_token(1,1)
        @token -= 1
        write_packet_raw(str)
      end
    end
  end

end

class PassivePacketHandler < PacketHandler
  def initialize(pkt_buf,peer_ip,port)
    super
  end
  
  def run_loop
    loop do
      pkt = extract_next_packet
      if pkt
        if pkt[:req][:is_request] && pkt[:req][:type] == "send init"
          # Write back ack right now
          ack_req = pkt[:req]
          # Compute loop number
          ack_cnt = (ack_req[:data_size].to_f / PACKET_SIZE ).ceil
          # Reply Ack
          req_to_reply(ack_req)
          ensure_token(1,ack_cnt + 1)
          #ensure_token(1,1)
          @token -= 1
          write_packet_req(ack_req,*pkt[:peer])
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
              if DCB_CEHCK_MAJOR_NUMBER
                if data_req[:task_no] != task_n
                  #puts "Task預期：#{task_n}，收到：#{data_req[:task_no]}"
                  #@pkt_buf.total_rx_loss[@port] += CLI_ACK_SLICE_PKT 
                  loss = true
                  break
                end
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
            if sub_buf.all? {|v| v } && ( SERVER_LOSS_RATE == 0.0 || rand > SERVER_LOSS_RATE )
              # 全都有
            else
              loss = true
            end
            # read ack
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
            if !loss && done
              #puts "DONE"
              break
            end
          end
        elsif pkt[:req][:is_request] && pkt[:req][:type] == "recv init"


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

  def run_loop
    i = 0
    pkts = []
    CLI_ACK_SLICE_PKT.times do |j|
      req = {}
      req[:is_request] = true
      req[:type] = "send data"
      req[:task_no] = i
      req[:sub_no] = [j]
      pkts[j] = pack_command(req)
    end
    ack_req = {}
    ack_req[:is_request] = true
    ack_req[:type] = "send ack"
    last_time = Time.now
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
      #puts "Start #{i} , interval = #{(Time.now - last_time)*1000}ms"
      last_time = Time.now
      #(rand(100)+1).times do
      done = false
      if DCB_CEHCK_MAJOR_NUMBER
        if CLIENT_LOSS_RATE == 0.0 || rand >= CLIENT_LOSS_RATE
          min = CLI_ACK_SLICE_PKT +  DCB_SDN_EXTRA_TOKEN_USED
          ensure_token(min,min)
          CLI_ACK_SLICE_PKT.times do |j|
            req = {}
            req[:is_request] = true
            req[:type] = "send data"
            req[:task_no] = i
            req[:sub_no] = [j]
            @total_send -= PACKET_SIZE
            current_send += PACKET_SIZE
            if @total_send <= 0
              req[:extra] = "DONE"
              done = true
            else
              req[:extra] = "CONTINUE"
            end
            write_packet_req(req)
            if done
              #puts "pre-DONE"
              @token += CLI_ACK_SLICE_PKT - 1 - j
              break
            end
          end
          @token -= CLI_ACK_SLICE_PKT 
        end
      else
        min = CLI_ACK_SLICE_PKT + DCB_SDN_EXTRA_TOKEN_USED
        ensure_token(min,min)
        CLI_ACK_SLICE_PKT.times do |j|
          written += write_packet_raw(pkts[j])
        end
        @token -= CLI_ACK_SLICE_PKT
      end
      if DCB_SENDER_REQUIRE_ACK
        @token -= 1
        reply_req = send_and_wait_for_ack(ack_req)
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
      #@total_send -= written
      #if @total_send <= 0
        #sleep
        #cleanup
        #Process.kill("INT",Process.pid)
      #end
      if @stop
        restore_token(@token)
        cleanup
        Process.kill("INT",Process.pid)
        break
      end
      #end # end times
      #sleep rand(1) + rand*3
    end
    #sleep rand(1)+rand
  end

  

  def execute_next_action
  end

  def cleanup
    super
  end
end

