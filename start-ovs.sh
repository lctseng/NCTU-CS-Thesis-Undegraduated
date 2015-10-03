#!/bin/sh 
modprobe openvswitch
modprobe gre
service openvswitch start
