require 'thread'

class PacketBuffer
  attr_reader :data
  attr_reader :available
  attr_reader :total_rx
  attr_reader :total_tx
  attr_reader :total_rx_loss
  attr_reader :total_tx_loss
  attr_accessor :notifier

  def initialize(address,range,active = false)
    @address =address
    @range = range
    @peers = {}
    @data = {}
    @total_rx = {}
    @total_tx = {}
    @total_rx_loss = {}
    @total_tx_loss = {}
    range.each do |port|
      @data[port] = []
      @peers[port] = UDPSocket.new
      if active
        @peers[port].connect(address,port)
      else
        @peers[port].bind(address,port)
      end
      @total_rx[port] = 0
      @total_tx[port] = 0
      @total_rx_loss[port] = 0
      @total_tx_loss[port] = 0
    end
    @available = DCB_SERVER_BUFFER_PKT_SIZE
    @data_lock = Mutex.new
    @previous_state = :go
  end

  def run_receive_loop
    loop do
      sleep 0.00001
      @data_lock.synchronize do
        5.times do 
          @peers.each do |port,sock|
            begin 
              pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
              size = pack[0].size
              pkt = {}
              pkt[:port] = port
              pkt[:size] = size
              pkt[:req] = parse_command(pack[0])
              if store_packet(pkt)
                # store success 
              else 
                @total_rx_loss[port] += 1
                # puts "Packet Buffer full when adding packet from #{port}!"
              end
            rescue IO::WaitReadable
            end
          end
        end
      end
      if DCB_SERVER_BUFFER_PKT_SIZE -  @available > DCB_SERVER_BUFFER_STOP_THRESHOLD
        if @previous_state == :go
          @previous_state = :stop
          notify_stop
        end
      else
        if @previous_state == :stop
          @previous_state = :go
          notify_go
        end
      end
    end
  end

  def notify_stop
    #puts "STOP!!"
  end

  def notify_go
    #puts "GO!!"
    
  end

  def store_packet(pkt)
    if @available > 0
      @available -= 1
      @data[pkt[:port]] << pkt
      return true
    else
      return false
    end
  end

  def write_packet_req(port,req)
    size = @peers[port].send(pack_command(req),0)
    @total_tx[port] += size
    size
  end

  def extract_block(port)
    block_data = []
    @data_lock.synchronize do
      remain = CLI_ACK_SLICE
      tgr_data = @data[port]
      while remain > 0 && !tgr_data.empty?
        pkt = tgr_data.shift
        size = pkt[:size]
        remain -= size
        block_data << pkt
        @available += 1
        @total_rx[port] += size
      end
    end
    #puts "Remain:#{DCB_SERVER_BUFFER_PKT_SIZE - @available}"
    block_data
  end


end
