#!/bin/bash
# script to start the LOS video streaming service
# 
#
# This starts h31proxy
# Assumption is that two udev rules exist, /dev/camera1 is a xraw source and /dev/stream1 is a h.264 source, should should be done during provisioning, typically make install

SUDO=$(test ${EUID} -ne 0 && which sudo)
LOCAL=/usr/local
CONFIG_DIR=/usr/local/h31/conf
echo "Starting H31Proxy.net"

cd ${LOCAL}/h31/h31proxy/ && ./h31proxy.net ${CONFIG_DIR}/mavproxy.conf ${CONFIG_DIR}/video-stream.conf