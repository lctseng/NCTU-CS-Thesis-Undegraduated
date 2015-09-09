#!/usr/bin/env ruby

HOST = []
10.times do |i|
    HOST[i+1] = "172.16.0.#{i+1}"
end

CONTROLLER_IP_SW = "172.16.0.253"
CONTROLLER_IP_HOST = "172.16.0.253"

CONTROLLER_PORT = 6000
