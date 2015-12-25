require_relative 'config'

NO_TYPE_REQUIRED = true if !defined? NO_TYPE_REQUIRED
require 'qos-lib'
require 'token_holder'


class TokenManager

  attr_reader :overall_holder_lock # locked for modify overall holders content
  

  def initialize
    @token_holders = {}
    @overall_holder_lock = Mutex.new
    refresh_holder_map
  end

  def add_new_agent(sock)
    # Read Identity
    msg = sock.recv(PACKET_SIZE)
    req = parse_command(msg)
    if req[:is_request] && req[:type] == "control register"
      name = req[:name]
      holder_list = req[:extra]
      puts "Register New Holder: #{name}"
      new_hold = TokenHolder.new(self,sock,name,holder_list)  
      @overall_holder_lock.synchronize do
        @token_holders[name] = new_hold
        refresh_holder_map
      end
    else
      # discard
      puts "未預期的Register：#{req}"
      sock.close
    end
  end

  def remove_holder(holder)
    name = holder.name
    @overall_holder_lock.synchronize do
      @token_holders.delete(name)
      refresh_holder_map
    end
  end
  
  # extract tokens from list of holders
  def extract_tokens(holders,min,max)
    #puts "Getting from #{holders.collect{|h| h.name}.inspect}"
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
    cnt = 0
    puts "============================="
    @token_holders.clone.each do |id,holder|
      print "[#{id}]:#{holder.token}, "
      cnt += 1
      if cnt >= 5
        puts
        cnt = 0
      end
    end
    puts 
  end

  # Map host to array of holder
  def refresh_holder_map
    @holder_map = {}
    PACKET_FLOWS.each do |target,holder_name_list|
      holders = []
      holder_name_list.each do |name|
        holder = @token_holders[name]
        if holder
          holders << holder
        else
          holders = []
          break
        end
      end
      @holder_map[target] = holders
    end
  end

  def inspect_holder_path
    puts "===========Holder Map=============="
    @holder_map.each do |key,arr|
      puts "Map for #{key}"
      arr.each do |hold|
        puts ">> #{hold.name}"
      end
    end
  end

  # from sender id, get list of holders
  def get_holders(id)
    @holder_map[id]
  end

  def restore_token(id,n)
    puts "RESTORE: #{id} : #{n}"
    @overall_holder_lock.synchronize do
      holders = get_holders(id)
      holders.each do |holder|
        holder.add_token(n)
      end
    end
  end

  def require_token(id,min,max)
    #puts "Require from:#{id}"
    @overall_holder_lock.synchronize do
      holders = get_holders(id)
      if holders.empty?
        @val = 0
      else
        @val =  extract_tokens(holders,min,max)
      end
    end
    #inspect_holders
    return @val
  end

end

