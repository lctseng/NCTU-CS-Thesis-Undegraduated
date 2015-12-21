#!/usr/bin/env ruby 

require_relative 'config'

require 'qos-info'
require 'signal_sender'
require 'signal_receiver'


$signal_sender.bind_port(DCB_SDN_CTRL_PORT)
thr_signal_accept = run_accept_thread


class Controller
  attr_reader :sender
  attr_reader :receiver
  attr_reader :host_token
  attr_reader :switch_token

  def initialize(sender)
    # Token init 
    @host_token = 0
    @switch_token = 0
    @token_lock = Mutex.new
    # bind sender
    @sender = sender
    @sender.originator = self
    # Connect to all switch and end host
    connect_end_hosts
    connect_switches

  end

  def connect_end_hosts
    @end_host = SignalReceiver.new(["172.16.0.1",DCB_SIGNAL_SENDER_PORT])
    @end_host.send_token_method = method(:send_token_host)
    @end_host.notifier = self
    @end_host.connect_peer
  end

  def connect_switches
    @switch = SignalReceiver.new(["127.0.0.1",DCB_SIGNAL_SENDER_PORT + dcb_get_sw_port_shift("s1")])
    @switch.send_token_method = method(:send_token_switch)
    @switch.notifier = self
    @switch.connect_peer
  end
 
  # NEED LOCKED!
  def dispatch_token(time,min_req = 0)
    min_token = [@host_token,@switch_token].min
    if min_token >= min_req
      used_min_token = @sender.dispatch_token(min_token,time)
      diff = min_token - used_min_token
      if diff > 0
        @host_token -= diff
        @switch_token -= diff
        #puts "#{diff} Token Dispatched, host = #{@host_token}, switch = #{@switch_token}"
      end
    end
  end

  def run_receiver_thread
    @thr_host = Thread.new do
      @end_host.run_loop
    end
    @thr_switch = Thread.new do
      @switch.run_loop
    end
  end

  #/////////////////
  # For Receiver API
  #/////////////////
  def show_cmd
    false
  end

  # dummy send go/stop
  def send_go(*args)

  end
  def send_stop(*args)

  end
  
  def send_token_host(token,time)
    @token_lock.synchronize do
      @host_token += token
      #puts "Host Token: #{@host_token} (+#{token})"
      dispatch_token(time)
    end
  end

  def send_token_switch(token,time)
    @token_lock.synchronize do
      @switch_token += token
      @switch_token = DCB_SDN_MAX_SWITCH_QUEUE_LENGTH if @switch_token > DCB_SDN_MAX_SWITCH_QUEUE_LENGTH
      #puts "Switch Token: #{@switch_token} (+#{token})"
      dispatch_token(time)
    end
  end

  #/////////////////
  # For Sender API
  #/////////////////
  def new_token_request(min,time)
    #puts "New request for token: #{min}"
    @token_lock.synchronize do
      dispatch_token(time,min) 
    end
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
  puts "Host = #{$controller.host_token}, Switch = #{$controller.switch_token}"
  sleep 0.1
end
