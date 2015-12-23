require 'thread'

class TokenGetter

  attr_reader :id
  attr_reader :min
  attr_reader :max
  attr_reader :getter_lock # protect min, max
    
  def initialize(master,id)
    @master = master
    @mgmt = master.token_mgmt
    @id = id
    @min = 0
    @max = 0
    @getter_lock = Mutex.new
    @req_ready = ConditionVariable.new
    run_getter_thread
  end

  def stop
    @thr_getter.exit
  end

  # getting data from master
  def run_getter_thread
    @thr_getter = Thread.new do
      loop do
        # Get req
        req_min = 0
        req_max = 0
        @getter_lock.synchronize do
          loop do
            if @min > 0 && @max > 0
              req_min = @min
              req_max = @max
              @min = 0
              @max = 0
              break
            else
              @req_ready.wait(@getter_lock)
            end
          end
        end
        # use req_min&req_max to require from master
        get_value = 0
        loop do
          get_value = @mgmt.require_token(@id,req_min,req_max)
          if get_value <= 0
            sleep 0.001
          else
            break
          end
        end
        # got token
        @master.give_token(@id,get_value)

      end
    end
  end

  def add_requirement(min,max)
    @getter_lock.synchronize do
      @min += min
      @max = [@max,max].max
      @req_ready.signal
    end
  end

end
