#!/usr/bin/env ruby 

require_relative 'config'

require 'qos-info'
require 'signal_sender'
require 'signal_receiver'


$signal_sender.bind_port(DCB_SDN_CTRL_PORT)
thr_signal_accept = run_accept_thread


# Hold a token to specific switch or receiver
class TokenHolder
  
  attr_reader :id
  attr_reader :token
  attr_reader :receiver
  
  def initialize(master,id,receiver)
    @master = master
    @id = id
    @receiver = receiver
    @token = 0
    @token_lock = @master.holder_lock#Mutex.new
  end
  #/////////////////
  # For Receiver API
  #/////////////////
  
  def send_token(token,time)
    @token_lock.synchronize do
      @token += token
    end
  end

  
  def show_cmd
    false
  end

  # dummy send go/stop
  def send_go(*args)

  end
  def send_stop(*args)

  end

  def run_receiver_thread
    @thr_recv = Thread.new do
      @receiver.run_loop
    end
  end

  def consume_token(val)
    @token -= val
  end

end

class TokenManager

  attr_reader :holder_lock

  def initialize
    @token_holders = {}
    @holder_lock = Mutex.new
    connect_end_hosts
    connect_switches
    create_holder_map
  end
  
  def connect_end_hosts
    RECEIVER_HOSTS.each_key do |id|
      recv = SignalReceiver.new([HOST_IP[id],DCB_SIGNAL_SENDER_PORT])
      hold = TokenHolder.new(self,id,recv)
      recv.send_token_method = hold.method(:send_token)
      recv.notifier = hold
      recv.connect_peer
      @token_holders[id] = hold
    end
  end

  def connect_switches
    QOS_INFO.each do |id,data|
      recv = SignalReceiver.new(["127.0.0.1",DCB_SIGNAL_SENDER_PORT + dcb_get_sw_port_shift(data[:sw]) + data[:eth].to_i])
      hold = TokenHolder.new(self,id,recv)
      recv.send_token_method = hold.method(:send_token)
      recv.notifier = hold
      recv.connect_peer
      @token_holders[id] = hold
    end
  end

  def run_receiver_thread
    @token_holders.each_value do |hold|
      hold.run_receiver_thread
    end
  end

  # extract tokens from list of holders
  def extract_tokens(holders,min,max)
    #puts "Getting from #{holders.collect{|h| h.id}.inspect}"
    min_free = holders.min_by {|h| h.token}.token
    if min_free < min
      return 0
    else
      dispatch = [min_free,max].min
      holders.each do |holder|
        holder.consume_token(dispatch)
      end
      return dispatch
    end
  end

  def inspect_holders
    @token_holders.each do |id,holder|
      print "[#{id}]:#{holder.token}, "
    end
    puts 
  end

  # Map host to array of holder
  def create_holder_map
    @holder_map = {}
    HOST_UPSTREAM_SWITCH.each do |host,sw|
      @holder_map[host] = [@token_holders[HOST_IP[HOST_UPSTREAM_HOST[host]]]] + sw.collect {|sw| @token_holders[sw]}
    end
  end

  # from sender id, get list of holders
  def get_holders(id)
    @holder_map[id]
  end

  def require_token(id,min,max)
    #puts "Require from:#{id}"
    @holder_lock.synchronize do
      holders = get_holders(id)
      @val =  extract_tokens(holders,min,max)
    end
    #inspect_holders
    return @val
  end

end

class Controller
  attr_reader :sender
  attr_reader :token_mgmt

  def initialize(sender)
    # bind sender
    @sender = sender
    @sender.originator = self
    # Token manager
    @token_mgmt = TokenManager.new
  end

 
  def run_receiver_thread
    @token_mgmt.run_receiver_thread
  end

  
  #/////////////////
  # For Sender API
  #/////////////////
  def new_token_request(id,min,max,time)
    #puts "New request for token: #{min}"
    send = 0
    loop do
      send = @token_mgmt.require_token(id,min,max)
      break if send > 0
      sleep 0.01
    end
    @sender.dispatch_token_id(id,send,time) 
  end

  def new_receiver

  end

  def name
    "CTRL"
  end




end


$controller = Controller.new($signal_sender)
$controller.run_receiver_thread


loop do
  $controller.token_mgmt.inspect_holders
  sleep 0.1
end
