#!/usr/bin/env ruby 
require_relative 'config'
require 'qos-info'

out_name = ARGV[0]
pattern_time = ARGV[1].to_f

PATTERN_POOL_PATH = "pattern_pool"

def write_sleep(file,pattern_time,sleep_time)
  if sleep_time > 0
    file.puts "sleep #{sleep_time}"
    pattern_time -= sleep_time
  end
  pattern_time
end


def generate_default_pattern(f,pattern_time)
  while pattern_time > 0
    # mice traffic
    if rand < 0.1
      10.times do
        f.puts rand(500*2**10)
        if rand < 0.5
          sleep_time = [rand(50)/100.0,pattern_time].min
          pattern_time = write_sleep(f,pattern_time,sleep_time)
        end
      end
    end

    # short sleep
    if rand < 0.5
      sleep_time = [rand(100)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # long sleep 
    if rand < 0.1
      sleep_time = [rand(1000)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # small traffic
    if rand < 0.5
      f.puts rand(UNIT_MEGA)
    end
    # burst traffic
    if rand < 0.05
      f.puts rand(10*UNIT_MEGA) + UNIT_MEGA
    end

  end


end


def generate_elephant_pattern(f,pattern_time)
  f.puts rand(10*UNIT_MEGA) + 1*UNIT_MEGA
  while pattern_time > 0
    # mice traffic
    if rand < 0.00
      10.times do
        f.puts rand(500*2**10)
        if rand < 0.5
          sleep_time = [rand(50)/100.0,pattern_time].min
          pattern_time = write_sleep(f,pattern_time,sleep_time)
        end
      end
    end

    # short sleep
    if rand < 0.0
      sleep_time = [rand(100)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # long sleep 
    if rand < 0.5
      sleep_time = [rand(1000)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # small traffic
    if rand < 0.1
      f.puts rand(30*UNIT_MEGA)
    end
    # burst traffic
    if rand < 0.05
      f.puts rand(100*UNIT_MEGA) + 50*UNIT_MEGA
    end

  end


end

def generate_elephant_long_sleep_pattern(f,pattern_time,options = {})
  long_time = options[:long_time] || 10
  long_rate = options[:long_rate] || 0.6
  small_rate = options[:small_rate] || 0.7
  large_rate = options[:large_rate] || 0.1
  while pattern_time > 0
    # mice traffic
    if rand < 0.05
      10.times do
        f.puts rand(500*2**10)
        if rand < 0.5
          sleep_time = [rand(50)/100.0,pattern_time].min
          pattern_time = write_sleep(f,pattern_time,sleep_time)
        end
      end
    end

    # short sleep
    if rand < 0.1
      sleep_time = [rand(100)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # long sleep 
    if rand < long_rate
      sleep_time = [rand(long_time * 100)/100.0,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end
    # small traffic
    if rand < small_rate
      f.puts rand(10*UNIT_MEGA)
    end
    # burst traffic
    if rand < large_rate
      size = rand(10*UNIT_MEGA) + UNIT_MEGA*5
      f.puts size
      sleep_time = [rand(100 * size*1 / UNIT_MEGA)/100.0 + size*0.5 / UNIT_MEGA,pattern_time].min
      pattern_time = write_sleep(f,pattern_time,sleep_time)
    end

  end


end

def generate_bursty_pattern(f,pattern_time)
  while pattern_time > 0
    if true
      if rand > 0.5
        f.puts "write #{rand(15*UNIT_MEGA) + 5*UNIT_MEGA}"
      else
        f.puts "read #{rand(15*UNIT_MEGA) + 5*UNIT_MEGA}"
      end
      if rand > 0.5 
        sleep_time = [rand(400)/100.0 + 5,pattern_time].min
        pattern_time = write_sleep(f,pattern_time,sleep_time)
      end
    end
  end
end


def generate_by_patching_files(f,pattern_time)
  # 整理pattern_pool中各檔案以及其持續時間(最短0.1)
  patterns = []
  Dir.foreach(PATTERN_POOL_PATH) do |f_name|
    f_name.force_encoding 'UTF-8'
    full_name = "#{PATTERN_POOL_PATH}/#{f_name}"
    next if !File.file?(full_name)
    content = ''
    time = 0.0
    size = 0
    File.open(full_name) do |f|
      while f.gets
        content += $_
        if ~ /sleep (\d+(\.\d+)?)/i
          time += $1.to_f
        else
          size += $_.to_i
        end
      end
    end
    if time <= 0.0
      content += "sleep 0.1\n"
      time = 0.1
    end
    patterns << [f_name,content,time,size]
  end
  # 開始湊數值
  while pattern_time > 0
    pattern = patterns.sample
    if pattern[3] > 100*2**20
      if rand < 0.1
        pattern_time = 0
      else
        next
      end
    end
    f.puts "# from: #{pattern[0]}"
    f.print pattern[1]
    pattern_time -= pattern[2]
  end



end

def generate_long_flow(f,pattern_time)
  f.puts 1000*UNIT_MEGA
end

def generate_pattern(out_name,pattern_time)
  File.open(sprintf(CLIENT_PATTERN_NAME_FORMAT,out_name),'w') do |f|
    #generate_default_pattern(f,pattern_time)
    #generate_elephant_pattern(f,pattern_time)
    #generate_elephant_long_sleep_pattern(f,pattern_time,{long_time: 10,long_rate: 0.01,large_rate: 0.5,small_rate: 0.9}) 
    generate_bursty_pattern(f,pattern_time)
    #generate_by_patching_files(f,pattern_time)
    #generate_long_flow(f,pattern_time)
  end
end

if out_name == "all"
  for out_name in 5001..5008
    generate_pattern(out_name,pattern_time)
  end
else
  generate_pattern(out_name,pattern_time)
end


