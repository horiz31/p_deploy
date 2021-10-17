#!/bin/bash
# This starts h31proxy

SUDO=$(test ${EUID} -ne 0 && which sudo)
LOCAL=/usr/local
CONFIG_DIR=/usr/local/h31/conf
echo "Starting H31Proxy.net"

cd ${LOCAL}/h31/h31proxy/ && ./h31proxy.net ${CONFIG_DIR}/mavproxy.conf ${CONFIG_DIR}/video-stream.conf 0,0
