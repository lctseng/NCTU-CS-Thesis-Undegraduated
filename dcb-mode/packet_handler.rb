class PacketHandler
  def initialize(pkt_buf,port)
    @pkt_buf = pkt_buf
    @block_buf = []
    @port = port
    @wait_for_packet = false
    @size_count = 0
  end

  def run_loop
    loop do
      pkt = extract_next_packet
      if pkt
        process_packet(pkt)
      elsif !@wait_for_packet
        execute_next_action
      end
    end
  end

  def extract_next_packet
    # process data in block
    if @block_buf.empty?
      @block_buf = @pkt_buf.extract_block(@port)
      if !@block_buf.empty?
        #puts "#{@port} Extracted block#: #{@block_buf.size}"
        #sleep (rand(3)+1)*0.0001
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
    @size_count += pkt[:size]
    if @size_count < CLI_ACK_SLICE
      #@wait_for_packet = true
    else
      # exceed
      sleep 0.001
      @size_count = 0
      @wait_for_packet = false
    end
    #puts "#{@port} ID: #{pkt[:req][:task_no]}"
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
    187.times do 
      loop do
        i += 1
        req = {}
        req[:is_request] = true
        req[:task_no] = i
        write_packet_req(req)
      end
      sleep 0.0001
    end
  end
  def execute_next_action

  end
end

