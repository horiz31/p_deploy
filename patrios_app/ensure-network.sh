#!/bin/bash
# usage:
#   ensure-network.sh [--dry-run]
#
# Ensure the network matches the settings in /etc/systemd/network.conf

SUDO=$(test ${EUID} -ne 0 && which sudo)
if [ "$1" == "--dry-run" ] ; then SUDO="echo ${SUDO}" ; fi

# make sure we have the environment variables set
if [ -z "$IFACE" ] || [ -z "$HOST" ] || [ -z "$NETMASK" ] ; then
	# https://unix.stackexchange.com/questions/79068/how-to-export-variables-that-are-set-all-at-once
	x=$(tail -n +2 /usr/local/h31/conf/network.conf) && set -a && eval $x && set +a
	# now we have the environment settings
fi

# https://unix.stackexchange.com/questions/290938/assigning-static-ip-address-using-nmcli
state=$(nmcli -f GENERAL.STATE c show "static-$IFACE" 2>/dev/null)
if [[ "$state" == *activated* ]] ; then         # take the interface down
        $SUDO nmcli c down "static-$IFACE"
fi
exist=$(nmcli c show "static-$IFACE" 2>/dev/null)
if [ ! -z "$exist" ] ; then     # delete the interface if it exists
        $SUDO nmcli c delete "static-$IFACE"
fi
# NB: we always start a new interface, because otherwise nmcli c mod keeps *adding* interfaces
$SUDO nmcli c add con-name "static-$IFACE" ifname $IFACE type ethernet ip4 $HOST/$NETMASK
if [[ "$GATEWAY" == *.* ]] ; then $SUDO nmcli c mod "static-$IFACE" ifname $IFACE gw4 $GATEWAY ; fi
$SUDO nmcli c up "static-$IFACE"

# Added from the update script
$SUDO nmcli con mod static-eth0 +ipv4.routes "224.0.0.0/8"
$SUDO nmcli con mod static-eth0 +ipv4.routes "239.0.0.0/8"
