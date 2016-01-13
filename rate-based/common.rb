
class Speed
  include Comparable
  attr_accessor :data

  def self.pkti(val)
    new(val)
  end

  def self.pkts(val)
    new((val*RATE_BASED_SEND_INTERVAL).ceil)
  end

  def self.mbps(val)
    pkts = (val * UNIT_MEGA / 8.0 / PACKET_SIZE).ceil
    self.pkts(pkts)
  end

  def initialize(pkti)
    @data = pkti
  end

  def pkti
    @data
  end

  def bps
    @data * PACKET_SIZE * 8.0 / RATE_BASED_SEND_INTERVAL
  end

  def mbps
    @data * PACKET_SIZE * 8.0 / UNIT_MEGA / RATE_BASED_SEND_INTERVAL
  end

  def +(rhs)
    Speed.new(@data + rhs.data)
  end

  def -(rhs)
    Speed.new(@data - rhs.data)
  end

  def -
    Speed.new(@data*-1)
  end

  def *(n)
    Speed.new (@data*n).ceil
  end

  def /(n)
    Speed.new (@data/n).ceil
  end

  def <=>(rhs)
    if rhs.is_a? self.class
      @data <=> rhs.data
    else
      @data <=> rhs
    end
  end

  def coerce(other)
    if other.is_a?(Numeric)
      [other, @data]
    else
      super
    end
  end

end



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


class ControlMessage

  TYPE_HOST = 1
  TYPE_SWITCH = 2
  TYPE_CONTROLLER = 3

  NONE = 0
  HOST_REGISTER = 1
  SWITCH_REGISTER = 2
  SWITCH_REPORT = 3
  HOST_CHANGE = 4
  SWITCH_CHANGE = 5

  attr_reader :id
  attr_reader :src_type
  attr_accessor :msg_type
  attr_accessor :spd
  attr_accessor :qlen

  def self.controller(msg_type = NONE)
    new(TYPE_CONTROLLER,"",msg_type)
  end

  def self.host(id,msg_type = NONE)
    new(TYPE_HOST,id,msg_type)
  end
  
  def self.switch(id,msg_type = NONE)
    new(TYPE_SWITCH,id,msg_type)
  end
  
  def self.recv(receiver)
    msg =  receiver.recv(RATE_BASED_CTRL_MSG_LEN)
    raise RuntimeError,"Cannot receive correct control message size!" if msg.size < RATE_BASED_CTRL_MSG_LEN
    unpack(msg)
  end

  def self.unpack(msg)
    fields = msg.split(";")
    # basic unpack
    src_type = fields[1].to_i
    id = fields[2]
    msg_type = fields[3].to_i
    ins = new(src_type,id,msg_type)
    # unpack by category
    case msg_type
    when HOST_REGISTER,SWITCH_REGISTER
      # do nothing
    when HOST_CHANGE,SWITCH_CHANGE
      ins.spd = fields[4].to_i
    when SWITCH_REPORT
      ins.spd = fields[4].to_i
      ins.qlen = fields[5].to_i
    else
      raise RuntimeError,"Cannot unpack: unknown msg_type"
    end
    ins
  end

  def initialize(src_type,id,msg_type = NONE)
    @src_type = src_type
    @id = id
    @msg_type = msg_type
    @spd = 0
    @qlen = 0
  end

  def pack
    msg = basic_pack
    case @msg_type
    when HOST_REGISTER,SWITCH_REGISTER
      # do nothing
    when HOST_CHANGE,SWITCH_CHANGE
      msg += "#{@spd};"
    when SWITCH_REPORT
      msg += "#{@spd};#{@qlen};"
    else
      raise RuntimeError,"Unable to pack control message: unknown msg_type"
    end
    pack_padding(msg)
  end

  def basic_pack
    "CTRL_MSG;#{@src_type};#{@id};#{@msg_type};"
  end

  def pack_padding(msg)
    if msg.size < RATE_BASED_CTRL_MSG_LEN
      msg + "-"*(RATE_BASED_CTRL_MSG_LEN - msg.size - 1) + ";"
    else
      msg
    end
  end

  def send(sender,flag)
    sender.send(self.pack,flag)
  end

  
  
  

end
