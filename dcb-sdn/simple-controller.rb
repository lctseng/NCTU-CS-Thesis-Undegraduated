#!/usr/bin/env ruby 

require_relative 'config'

require 'socket'
require 'qos-info'
require 'signal_sender'
require 'signal_receiver'


$signal_sender.bind_port(DCB_SDN_CTRL_PORT)
thr_signal_accept = run_accept_thread

$signal_receiver = SignalReceiver.new(["172.16.0.1",DCB_SDN_CTRL_PORT])
$signal_receiver.connect_peer


class SignalPasser

  attr_reader :previous_state
  attr_reader :recv
  attr_reader :send
  attr_reader :token

  def initialize(recv,send)
    @recv = recv
    @send = send
    @recv.notifier = self
    @send.originator = self
    @token_lock = Mutex.new
    @token = 0
  end

  def send_go(time)
    #puts "#{$sw}: GO!"
    #sleep 0.001
    @send.notify_go(time)
    @previous_state = :go
  end

  def send_stop(time)
    #puts "#{$sw}: STOP!"
    #sleep 0.001
    @send.notify_stop(time)
    @previous_state = :stop
  end

  def send_token(token,time)
    @token_lock.synchronize do
      @token += token
      #puts "Token: #{@token} (+#{token})"
      @token = @send.dispatch_token(@token,time)
    end
  end
  
  def new_token_request(min,time)
    #puts "New request for token: #{min}"
    @token_lock.synchronize do
      if @token >= min
        @token = @send.dispatch_token(@token,time)
      end
    end
  end

  def new_receiver

  end

  def name
    "CTRL"
  end

  def show_cmd
    false
  end
end

$signal_passer = SignalPasser.new($signal_receiver,$signal_sender)

thr_signal_read = Thread.new do
  $signal_receiver.run_loop
end



loop do
  puts "Token Remain: #{$signal_passer.token}"
  sleep 0.1
end
