#!/bin/bash
# usage:
#   ensure-mender.sh
#
# This script ensures that mender it installed and setup

DRY_RUN=false
LOCAL=/usr/local
SUDO=$(test ${EUID} -ne 0 && which sudo)
DEVICE_TYPE="jetson-nano-emmc"

$SUDO chmod +x scripts/get-mender.sh
# unfortunately we have to "setup" the service like this and disable the client
$SUDO ./scripts/get-mender.sh -- \
        --device-type $DEVICE_TYPE \
        --demo \
        --server-ip 127.0.0.1

# Remove the client as we wont be connecting to external server... for now.
$SUDO systemctl stop mender-client
$SUDO systemctl disable mender-client
$SUDO systemctl mask mender-client

# Remove the websocket app that will attempt to connect to server... for now.
$SUDO systemctl stop mender-connect
$SUDO systemctl disable mender-connect
$SUDO systemctl mask mender-connect

