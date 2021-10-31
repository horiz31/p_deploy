#!/bin/bash
# update to version 2
SUDO=$(test ${EUID} -ne 0 && which sudo)

$SUDO systemctl stop mavproxy
$SUDO systemctl disable mavproxy
$SUDO rm /lib/systemd/system/mavproxy.service

$SUDO systemctl stop audio-streamer
$SUDO systemctl disable audio-streamer
$SUDO rm /lib/systemd/system/audio-streamer.service

rm -rf /usr/local/src/patrios/*.* Makefile

cp -r patrios_app/. /usr/local/src/patrios/.
/usr/local/src/patrios/ensure-cockpit.sh
$SUDO apt-get install nano
$SUDO apt-get install apt-offline

$SUDO nmcli con mod static-eth0 +ipv4.routes "224.0.0.0/8"
$SUDO nmcli con mod static-eth0 +ipv4.routes "239.0.0.0/8"

make -C /usr/local/src/patrios install
make -C /usr/local/src/patrios provision

$SUDO chown -R h31 /usr/local/h31
