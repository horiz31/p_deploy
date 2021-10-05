#!/bin/bash
# update H31Proxy by itself
SUDO=$(test ${EUID} -ne 0 && which sudo)

$SUDO systemctl stop h31proxy
$SUDO systemctl stop camera-switcher

cp -r patrios_app/h31proxy/h31proxy.net /usr/local/h31/h31proxy/.

echo "H31Proxy updated to version 0.1d"
echo "Restarting system services now..."

$SUDO systemctl start h31proxy
$SUDO systemctl start camera-switcher

