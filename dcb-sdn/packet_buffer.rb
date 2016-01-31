require_relative 'config'
require 'thread'
require 'token_adder'

class PacketBuffer

  include TokenAdder

  attr_reader :data
  attr_reader :available
  attr_reader :total_rx
  attr_reader :total_tx
  attr_reader :total_rx_loss
  attr_reader :total_tx_loss
  attr_accessor :notifier
  attr_reader :disk_lock
  attr_reader :send_ok

  attr_reader :control_api
  attr_reader :active
  attr_reader :my_addr


  def initialize(my_addr,peer_addr,range,active = false)
    @active = active
    @last_check = Time.at(0)
    @my_addr = my_addr
    @peer_addr = peer_addr
    @range = range
    @peers = {}
    @sock_data = {}
    @data = {}
    @total_rx = {}
    @total_tx = {}
    @total_rx_loss = {}
    @total_tx_loss = {}
    @peers_list = []
    @data_locks = {}
    @cond_var = {}
    @writer_locks = {}
    @writer_cond = {}
    @write_queue = {}
    range.each do |port|
      @cond_var[port] = ConditionVariable.new 
      @data_locks[port] = Mutex.new
      @writer_locks[port] = Mutex.new
      @writer_cond[port] = ConditionVariable.new
      @write_queue[port] = []
      @data[port] = []
      sock = UDPSocket.new
      @peers[port] = sock
      @sock_data[sock] = port
      @peers_list << sock
      if active
        @peers[port].bind(my_addr,port)
        @peers[port].connect(peer_addr,port)
      else
        @peers[port].bind(my_addr,port)
      end
      @total_rx[port] = 0
      @total_tx[port] = 0
      @total_rx_loss[port] = 0
      @total_tx_loss[port] = 0
    end
    @available = DCB_SERVER_BUFFER_PKT_SIZE
    @free_token = [(@available * 0.9).round,DCB_SDN_MAX_TOKEN].min
    @temp_free_token = 0
    @token_lock = Mutex.new
    #@data_lock = Mutex.new
    @disk_lock = Mutex.new
    @send_ok = false
    @stop_receive = false
  end


  def post_register
    notify_token  
  end
 


  def end_connection(port)

  end
  
  def end_receive
    @stop_receive = true
  end

  def name
    "Host"
  end

  def show_cmd
    true
  end

  def send_token(token,time)
  end


  def run_receive_loop
    loop do
      ready = IO.select(@peers_list)
      ready[0].each do |sock|
        port = @sock_data[sock]
        acks = []
        @data_locks[port].synchronize do
          loop do
            begin
              pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
              size = pack[0].size
              pkt = {}
              pkt[:port] = port
              pkt[:size] = size
              req = parse_command(pack[0])
              pkt[:req] = req
              pkt[:msg] = pack[0]
              pkt[:peer] = [pack[1][3],pack[1][1]]
              # reply ack 
              if  DCB_SDN_PREMATURE_ACK && req[:is_request] && req[:type] == "data ack"
                req[:is_request] = false
                req[:is_reply] = true
                acks << pkt
                @total_rx[port] += PACKET_SIZE
                add_free_token(1)
              elsif store_packet(pkt)
                # store success 
              else 
                @total_rx_loss[port] += 1
                add_free_token(1)
                #puts "Packet Buffer full when adding packet from #{port}!"
              end
            rescue IO::WaitReadable
              break
            end
          end
        end
        @cond_var[port].signal
        if !acks.empty?
          @writer_locks[port].synchronize do
            @write_queue[port] += acks
            @writer_cond[port].signal
          end
        end
      end
      stop_go_check
    end
  end

  def writer_loop(port)
    loop do
      @writer_locks[port].synchronize do 
        if @write_queue[port].empty?
          @writer_cond[port].wait(@writer_locks[port])
        end
        @write_queue[port].each do |pkt|
          write_packet_req(port,pkt[:req],*pkt[:peer])
        end
        @write_queue[port] = []
      end
    end
  end

  def new_receiver
    if @free_token > 0
      notify_token
    end
  end

  def stop_go_check
    if @free_token > 0
      notify_token
    end
  end

  def stop_go_check_loop
    loop do
      sleep 1
      stop_go_check
    end
  end


  def notify_token
    if @control_api
      if @free_token >= DCB_RECEIVER_FEEDBACK_THRESHOLD
        @token_lock.synchronize do
          result = control_add_token(@free_token)
          if result
            @free_token = 0
          end
        end
      end
    end
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

  def write_packet_req(port,req,*peer)
    #while !@send_ok
    #  sleep 0.001
    #end
    size = @peers[port].send(pack_command(req),0,*peer)
    @total_tx[port] += size
    size
  end
  
  def write_packet_raw(port,str,*peer)
    size = @peers[port].send(str,0,*peer)
    @total_tx[port] += size
    size
  end

  def extract_next_packet(port,timeout)
    sock = @peers[port]
    ready = IO.select([sock],[],[],timeout)
    return nil if !ready
    pack = sock.recvfrom(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
    size = pack[0].size
    pkt = {}
    pkt[:port] = port
    pkt[:size] = size
    req = parse_command(pack[0])
    pkt[:req] = req
    pkt[:msg] = pack[0]
    pkt[:peer] = [pack[1][3],pack[1][1]]
    @total_rx[port] += PACKET_SIZE
    add_free_token(1)
    stop_go_check
    pkt
  end

  def extract_block(port,timeout = nil)
    block_data = []
    get_size_a = [0] 
    @data_locks[port].synchronize do
      tgr_data = @data[port]
      if tgr_data.empty?
        @cond_var[port].wait(@data_locks[port],timeout)
        tgr_data = @data[port]
      end
      if !tgr_data.empty?
        tgr_size = tgr_data.size
        get_size_a[0] = [tgr_size,CLI_ACK_SLICE_PKT].min
        
        #get_size = [tgr_size,1].min
        block_data += tgr_data[0,get_size_a[0]]
        @data[port] = tgr_data[get_size_a[0],tgr_size]
        @available += get_size_a[0]
      end
    end
    add_free_token(get_size_a[0])
    @total_rx[port] += PACKET_SIZE * block_data.size
    stop_go_check
    block_data
  end

  def add_free_token(token)
    @token_lock.synchronize do
      @free_token += token
    end
  end

end
