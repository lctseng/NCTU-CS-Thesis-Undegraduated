#!/bin/sh -ex
date=`date "+%Y-%m-%d_%H_%M_%S"`
time_base=`./time_base_finder.rb __last__`
./host_speed_log_to_json.rb __last__ $time_base
./switch_info_log_to_json.rb __last__ $time_base
name=$1
prefix=${name:=${date}}
tar -cf "archive/${prefix}.tar" log pattern json
