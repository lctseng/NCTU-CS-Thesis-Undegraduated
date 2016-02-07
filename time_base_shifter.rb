#!/usr/bin/env ruby 
$base_time = Time.now.to_f

# Find the smallest time amount the files
# Hosts
def filter_host(filename)
  if File.exist?(filename)
    File.open(filename) do |f|
      while f.gets
        if ~ /^(\d+(\.\d+)?) /i
          time = $_.split.shift.to_f
          $stderr.puts "host:#{filename}:#{time}"
          $base_time = [time,$base_time].min
          break
        end
      end
    end
  end
end

def shift_log(filename)
  if File.exist?(filename)
    out_name = filename + ".out"
    out_file = File.open(out_name,"w")
    File.open(filename) do |f|
      while f.gets
        if ~ /^(\d+(\.\d+)?) (.+)/i
          old_time = $1.to_f
          new_time = old_time - $base_time
          out_file.puts "#{sprintf("%.2f",new_time)} #{$3}"
        end
      end
    end
  end
end

$files = ["total"]
# Hosts
for port in 5001..5008
  $files << sprintf("client_%s",port)
end

# find base
$files.each do |filename|
  filter_host(filename)
end

# Output
$stderr.puts "Time base: #{$base_time}"

# Shift Time
$files.each do |filename|
  shift_log(filename)
end
