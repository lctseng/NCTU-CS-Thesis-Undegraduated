#!/usr/bin/env ruby 

require_relative 'config'

require 'thread'
require 'socket'
require 'qos-info'
require 'token_manager'


class Controller
  attr_reader :token_mgmt

  def initialize
    # bind control port 
    @server = TCPServer.new("0.0.0.0",DCB_SDN_CTRL_PORT)
    # Token manager
    @token_mgmt = TokenManager.new
  end
 
  # Receive new client
  def run_main_loop
    loop do
      new_sock = @server.accept
      @token_mgmt.add_new_agent(new_sock)
    end
  end

end


$controller = Controller.new
thr_control = Thread.new do
  $controller.run_main_loop
end


loop do
  $controller.token_mgmt.inspect_holders
  sleep 0.1
end
