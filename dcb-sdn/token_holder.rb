# /////////// QOS LIB /////////////
require_relative 'config'

NO_TYPE_REQUIRED = true if !defined? NO_TYPE_REQUIRED
require 'qos-lib'
# /////////// QOS LIB ///////////// 
require 'token_getter'
require 'thread'


# Hold a token to specific switch or receiver
class TokenHolder
  
  attr_reader :name
  attr_reader :token # Receive Buffer Token
  attr_reader :sock
  
  def initialize(master,sock,name,holder_list)
    @master = master
    @name = name
    @sock = sock
    @token = 0
    @token_lock = Mutex.new # Lock for holder internal token
    create_getters(holder_list.split(','))
    run_receive_thread
  end

  def token_mgmt
    @master
  end

  def create_getters(id_array)
    @getters = {}
    id_array.each do |id|
      @getters[id] = TokenGetter.new(self,id)
    end
  end

  def close_holder
    # puts "Holder #{@name} closed"
    # Stop Getters
    @getters.each_value do |getter|
      getter.stop
    end
    # Call master's cleanup
    @master.remove_holder(self)
  end

  def run_receive_thread
    @thr_receive = Thread.new do
      loop do
        str = @sock.recv(100)
        if !str
          close_holder
          break
        else
          data = str.split
          cmd = data[0]
          time = data[1]
          case cmd # cmd
          when "ADD_TOKEN"
            # ADD_TOKEN TIME VALUE
            add_token(data[2].to_i)
          when "GET_TOKEN"
            # GET_TOKEN TIME ID MIN MAX
            get_token(data[2],data[3].to_i,data[4].to_i) 
          end
        end
      end
    end
  end

  def add_token(n)
    @token_lock.synchronize do
      @token += n
    end
  end

  def consume_token(n)
    @token_lock.synchronize do
      @token -= n
    end
  end
  
  def get_token(id,min,max)
    getter = @getters[id]
    if getter
      getter.add_requirement(min,max)
    else
      puts "[Error] Getter #{id} 不存在！"
    end
  end

  def give_token(id,n)
    @sock.puts "GIVE_TOKEN #{Time.now.to_f} #{id} #{n}"
  end


end
