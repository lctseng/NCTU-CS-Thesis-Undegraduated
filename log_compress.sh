#!/bin/sh -ev
date=`date "+%Y-%m-%d_%H_%M_%S"`
./host_speed_log_to_json.rb
./switch_info_log_to_json.rb `cat last_setup_mode.tmp`
tar -czf "${date}.json.tar.gz" json
