require_relative 'config'

NO_TYPE_REQUIRED = true if !defined? NO_TYPE_REQUIRED
require 'qos-lib'
class ControlAPI
  
  attr_reader :token_adder # new tokens comes from here
  attr_reader :address
  attr_reader :name


  def initialize(addr,name,holder_list)
    # member init
    @address = addr
    @name = name
    @handlers = {} # key by id(IP:PORT)
    @holder_list = holder_list
    # startup
    connect_controller
  end


  def connect_controller
    # req 
    req = {}
    req[:is_request] = true
    req[:type] = "control register"
    req[:name] = @name
    req[:extra] = @holder_list
    req
    # connect
    @controller = TCPSocket.new(DCB_SDN_CTRL_ADDR,DCB_SDN_CTRL_PORT)
    @controller.send(pack_command(req),0)
  end

  # Register-related routine (passive)
  def register_token_adder(adder)
    @token_adder = adder
  end

  def add_token(n)
    str = "ADD_TOKEN #{Time.now.to_f} #{n}"
    pad = ' '*(100-str.size)
    @controller.send(str + pad,0)
    return true
  end
  
  def restore_token(handler,n)
    str = "RESTORE_TOKEN #{Time.now.to_f} #{handler.id} #{n}"
    pad = ' '*(100-str.size)
    @controller.send(str + pad,0)
  end

  

  def register_handler(handler)
    @handlers[handler.id] = handler
    handler.token_getter = self
  end

  def get_token(handler,min,max)
    #puts "#{handler.id} Requiring token :#{min},#{max}" if handler.is_a?(ActivePacketHandler)
    # send message 
    str =  "GET_TOKEN #{Time.now.to_f} #{handler.id} #{min} #{max}"
    pad = ' '*(100-str.size)
    #@req_time = Time.now
    @controller.send(str + pad,0)
    # sleep on cond var.
    handler.token_ready.wait(handler.token_lock)
  end


  def close
    @controller.close
  end

  # Loop-related routine (active)
  def run_main_loop
    loop do
      # receive GIVE_TOKEN from controller
      begin
        str = @controller.recv(100)
      rescue
        break
      end
      data = str.split
      cmd = data[0]
      time = data[1].to_f
      case cmd
      when "GIVE_TOKEN"
        # GIVE_TOKEN TIME ID VALUE
        id = data[2]
        value = data[3].to_i
        #puts "#{id} Token #{value} Got, delay = #{sprintf("%7.3f",(Time.now.to_f - @req_time.to_f)*1000)}ms"
        @handlers[id].give_token(value,time)
      end
    end
  end
end
