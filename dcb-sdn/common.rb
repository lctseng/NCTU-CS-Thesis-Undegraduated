class IntervalWait
  def initialize
    @last_sleep = nil
    @last_spin = nil
  end

  def sleep(val)
    if @last_sleep
      diff = Time.now - @last_sleep
      sleep_val = val - diff
    else
      # No last 
      sleep_val = val
    end
    Kernel.sleep sleep_val if sleep_val > 0
    @last_sleep = Time.now
  end
  
  def spin(val)
    if @last_spin
      diff = Time.now - @last_spin
      spin_val = val - diff
    else
      # No last 
      spin_val = val
    end
    spin_time spin_val if spin_val > 0
    @last_spin = Time.now
  end

  private

  def spin_time(wait_time)
    last_time = Time.now
    loop do
      this_time = Time.now
      if this_time - last_time >= wait_time
        break
      end
    end

  end

end

class Timing
  def self.start
    new
  end

  def initialize
    start
  end

  def start
    @start = Time.now
  end

  def check
    (Time.now - @start) * 1000
  end
  
  def end
    val = (Time.now - @start) * 1000
    @start = Time.now
    val
  end
  
end
