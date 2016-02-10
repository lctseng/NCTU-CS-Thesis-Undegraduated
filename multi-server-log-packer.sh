#!/bin/sh -ev
cd 172.16.0.1 && ./time_base_shifter.rb && cd ..
cd 172.16.0.2 && ./time_base_shifter.rb && cd ..
./sum_log.rb 172.16.0.1/total.out,172.16.0.2/total.out > 172.16.0.1/global.out
./sum_log.rb 172.16.0.1/total.out,172.16.0.2/total.out > 172.16.0.2/global.out
cd 172.16.0.1 && ./pack_log.rb $1-multi-1 && cd ..
cd 172.16.0.2 && ./pack_log.rb $1-multi-2 && cd ..
