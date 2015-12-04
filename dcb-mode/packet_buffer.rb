require 'thread'

class PacketBuffer

  attr_reader :data
  attr_reader :available
  attr_reader :total_rx
  attr_reader :total_tx
  attr_reader :total_rx_loss
  attr_reader :total_tx_loss
  attr_accessor :notifier
  attr_reader :disk_lock
  attr_reader :send_ok
  attr_reader :previous_state

  def initialize(address,range,active = false)
    @address =address
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
    range.each do |port|
      @cond_var[port] = ConditionVariable.new 
      @data_locks[port] = Mutex.new
      @data[port] = []
      sock = UDPSocket.new
      @peers[port] = sock
      @sock_data[sock] = port
      @peers_list << sock
      if active
        @peers[port].bind("0.0.0.0",port)
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
    @previous_state = :go
    #@data_lock = Mutex.new
    @disk_lock = Mutex.new
    @send_ok = false
=begin
    @recv_buff = [false]*CLI_ACK_SLICE_PKT
    @recv_count = 0
    @task_cnt = 0
=end
  end

  def send_stop
    @send_ok = false
  end

  def send_go
    @send_ok = true
  end


  def run_port_receive_loop(port)
    sock = @peers[port]
    loop do
      ready = IO.select([@peers[port]])
      @data_locks[port].synchronize do
        ready[0].each do |sock|
          loop do
            begin 
              pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
              size = pack[0].size
              pkt = {}
              pkt[:port] = port
              pkt[:size] = size
              pkt[:req] = parse_command(pack[0])
              pkt[:msg] = pack[0]
              pkt[:peer] = pack[1]
              if store_packet(pkt)
                # store success 
              else 
                @total_rx_loss[port] += 1
                puts "Packet Buffer full when adding packet from #{port}!"
              end
            rescue IO::WaitReadable
              break
            end
          end
        end
      end
=begin
      sleep 0.000001
      CLI_ACK_SLICE_PKT.times do 
        noread = true
        begin 
          pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
          size = pack[0].size
          pkt = {}
          pkt[:port] = port
          pkt[:size] = size
          pkt[:req] = parse_command(pack[0])
          pkt[:msg] = pack[0]
          @data_locks[port].synchronize do
            if store_packet(pkt)
              # store success 
            else 
              @total_rx_loss[port] += 1
              puts "Packet Buffer full when adding packet from #{port}!"
            end
            noread = false
          end
        rescue IO::WaitReadable
        end
        if noread
          #print "No read"
          sleep 0.00001
        end
      end
=end
      stop_go_check
    end


  end

  def run_receive_loop
    loop do
      ready = IO.select(@peers_list)
      ready[0].each do |sock|
        port = @sock_data[sock]
        @data_locks[port].synchronize do
          loop do
            begin
              pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
              size = pack[0].size
              pkt = {}
              pkt[:port] = port
              pkt[:size] = size
              pkt[:req] = parse_command(pack[0])
              pkt[:msg] = pack[0]
              pkt[:peer] = [pack[1][3],pack[1][1]]
              if store_packet(pkt)
                # store success 
              else 
                @total_rx_loss[port] += 1
                puts "Packet Buffer full when adding packet from #{port}!"
              end
            rescue IO::WaitReadable
              break
            end
          end
        end
        @cond_var[port].signal
      end
=begin
      #@data_lock.synchronize do
        #CLI_ACK_SLICE_PKT.times do 
          noread = true
          @peers.each do |port,sock|
            begin 
              pack = sock.recvfrom_nonblock(PACKET_SIZE)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
              size = pack[0].size
              pkt = {}
              pkt[:port] = port
              pkt[:size] = size
              pkt[:req] = parse_command(pack[0])
              pkt[:msg] = pack[0]
              if store_packet(pkt)
                # store success 
              else 
                @total_rx_loss[port] += 1
                 puts "Packet Buffer full when adding packet from #{port}!"
              end
              noread = false
            rescue IO::WaitReadable
            end
          end
          if noread
            #print "No read"
            #sleep 0.00001
          end
        #end
      #end
=end

      stop_go_check
    end
  end

  def stop_go_check
    if DCB_SERVER_BUFFER_PKT_SIZE -  @available > DCB_SERVER_BUFFER_STOP_THRESHOLD
      if @previous_state == :go
        @previous_state = :stop
        notify_stop
      end
    elsif DCB_SERVER_BUFFER_PKT_SIZE -  @available < DCB_SERVER_BUFFER_GO_THRESHOLD
      if @previous_state == :stop
        @previous_state = :go
        notify_go
      end
    end

  end

  def notify_stop
    if @notifier
      @notifier.notify_stop
    end
  end

  def notify_go
    if @notifier
      @notifier.notify_go
    end

  end

  def store_packet(pkt)
=begin
    @total_rx[pkt[:port]] += pkt[:size]

    task_n = pkt[:req][:task_no]
    if task_n != @task_cnt
      puts "錯誤的大編號：#{task_n}，預期：#{@task_cnt}"
      CLI_ACK_SLICE_PKT.times do |i|
        @recv_buff[i] = false
      end
      @total_rx_loss[pkt[:port]] += (CLI_ACK_SLICE_PKT - @recv_count  + CLI_ACK_SLICE_PKT * (task_n - @task_cnt - 1))
      @recv_count = 0
      @task_cnt = task_n
    end

    sub_n = pkt[:req][:sub_no][0]
    #puts "#{task_n}:#{sub_n}"
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
        @disk_lock.synchronize do
          #sleep 0.03
        end
        @task_cnt += 1
        #puts @task_cnt
      else
        # not full
      end
    end
    return true 



=end
    if @available > 0
      @available -= 1
      @data[pkt[:port]] << pkt
      return true
    else
      return false
    end
  end

  def write_packet_req(port,req,*peer)
    while !@send_ok
      sleep 0.001
    end
    size = @peers[port].send(pack_command(req),0,*peer)
    @total_tx[port] += size
    size
  end

  def extract_block(port,timeout = nil)
    block_data = []
    @data_locks[port].synchronize do
      tgr_data = @data[port]
      if tgr_data.empty?
        @cond_var[port].wait(@data_locks[port],timeout)
        tgr_data = @data[port]
      end
      if !tgr_data.empty?
        remain = CLI_ACK_SLICE
        tgr_size = tgr_data.size
        get_size = [tgr_size,CLI_ACK_SLICE_PKT].min
        block_data += tgr_data[0,get_size]
        @data[port] = tgr_data[get_size,tgr_size]
        @available += get_size
      end
    end
    @total_rx[port] += PACKET_SIZE * block_data.size
    #puts "Remain:#{DCB_SERVER_BUFFER_PKT_SIZE - @available}"
    stop_go_check
    block_data
  end


end
