#!/bin/bash
# update H31Proxy by itself
SUDO=$(test ${EUID} -ne 0 && which sudo)

cp -r patrios_app/h31proxy/h31proxy.net /usr/local/src/h31proxy/.

echo "H31Proxy updated to version 0.1b"
echo "Restarting system services now..."

$SUDO systemctl restart h31proxy
$SUDO systemctl restart camera-switcher

