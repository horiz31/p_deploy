#!/bin/bash
# usage:
#   postinstall.sh [--dry-run]
#
# Perform steps needed to configure a factory system.
#
# The script is based on the USER id:
#
# USER=nvidia
#   1) create h31:users with default password and extra groups
#   2) copy files to /usr/local/src/patrios
#   3) spare
#   4) delete autologin (see https://github.com/climr/patrios_app/issues/8)
#   5) change hostname to serial number
#   6) tell user that a reboot will occur and that they are to login, and re-run 'make postinstall'
#   7) reboot
#
# USER=h31
#   1) delete nvidia user
#   2) generate a new ssh key
#   3) tell user to run 'make dependencies', 'make install', and 'make provision' commands

CAMERA_STREAMER=/usr/local/src/camera-streamer
NEWUSER=h31
NEWGROUP=users
NEWGROUPS="adm,audio,dialout,sudo,video"
SUDO=$(test ${EUID} -ne 0 && which sudo)
# https://stackoverflow.com/questions/46163678/get-rid-of-warning-command-substitution-ignored-null-byte-in-input
SN=$(python serial_number.py | tr -d '\0')
SYSCFG=/usr/local/h31/conf

DRY_RUN=false
while (($#)) ; do
	if [ "$1" == "--dry-run" ] ; then DRY_RUN=true ; SUDO=echo ; #set -x ;
	fi
	shift
done

function interactive {
	local result
	read -p "${2}? ($1) " result
	if [ -z "$result" ] ; then result=$1 ; elif [ "$result" == "*" ] ; then result="" ; fi
	echo $result
}

case "$USER" in
	nvidia)
		# 1) create h31 with default password and extra groups
		if ! x=$(id $NEWUSER) ; then
			$SUDO useradd -g $NEWGROUP -G $NEWGROUPS -m -s /bin/bash $NEWUSER && \
				echo "Please enter password for $NEWUSER:" &&
				$SUDO passwd $NEWUSER
		fi
		# 2) copy files to /usr/local/src/patrios
		if [ ! -d /usr/local/src/patrios ] ; then
			$SUDO mkdir -p /usr/local/src
			$SUDO cp -rf ./ /usr/local/src/patrios
			$SUDO chown -R $NEWUSER:$NEWGROUP /usr/local/src/patrios
		fi
		# 3) create /usr/local/h31 if needed and make h31 user own it
		if [ ! -d /usr/local/h31 ] ; then
			$SUDO mkdir -p /usr/local/h31
		fi
		$SUDO chown -R $NEWUSER:$NEWGROUP /usr/local/h31
		# https://www.linuxquestions.org/questions/linux-server-73/motd-or-login-banner-per-user-699925/
		cat > /tmp/99-motd.$$ <<-EO1
# only for interactive shells
if [[ \$- == *i* ]]
then
	if [ -e \$HOME/.motd ] ; then cat \$HOME/.motd ; fi
fi
EO1
		$SUDO install -Dm644 /tmp/99-motd.$$ /etc/profile.d/99-motd.sh
		cat > /tmp/.motd <<-EO2
*** Please complete the postinstall stage by issuing the following:
make -C /usr/local/src/patrios postinstall
EO2
		$SUDO install -D -t /home/$NEWUSER -o $NEWUSER -g $NEWGROUP /tmp/.motd
		# 3) spare
		# 4) delete autologin (see https://github.com/climr/patrios_app/issues/8)
		# https://lists.debian.org/debian-user/2015/09/msg00253.html
		# https://tldp.org/HOWTO/Text-Terminal-HOWTO-10.html#ss10.2
		cat > /tmp/$$.conf <<-EO3
[Service]
ExecStart=
ExecStart=-/sbin/agetty --keep-baud 115200 %I xterm-256color
EO3
		$SUDO install -Dm644 /tmp/$$.conf /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
		# https://forums.developer.nvidia.com/t/how-to-boot-jetson-nano-in-text-mode/73636/2
		# https://lunar.computer/posts/nvidia-jetson-nano-headless/
		for c in stop disable ; do $SUDO systemctl $c gdm3 ; done
		$SUDO systemctl set-default multi-user.target
		# 5) change hostname to serial number
		echo $SN > /tmp/$$.hostname
		$SUDO install -Dm644 /tmp/$$.hostname /etc/hostname
		$SUDO hostname $SN
		# 6) ensure that the internet is available
		if ! python ${CAMERA_STREAMER}/internet.py ; then
			echo "*** Internet must be available for the next step ***"
			echo ""
			nmcli c show
			echo ""
			if ! $DRY_RUN ; then
				#set -x
				ans=$(interactive "no" "Would you like to configure the network")
				if [[ "$ans" == y* ]] ; then
					echo "*** Please ensure that a GATEWAY is provided ***"
					echo ""
					make $SYSCFG/network.conf
				fi
			fi
		fi
		# 7) tell user that a reboot will occur and that they are to login, and re-run 'make postinstall'
		echo "*** System will REBOOT.  Please login with $NEWUSER (password as entered above)"
		echo "*** and run 'make -C /usr/local/src/patrios postinstall' again, following instructions"
		if ! $DRY_RUN ; then
			#set -x
			ans=$(interactive "no" "Ok to reboot")
			if [[ "$ans" == y* ]] ; then
				$SUDO reboot
			fi
		fi
		;;

	$NEWUSER)
		# 1) delete nvidia user
		$SUDO deluser --remove-home nvidia
		# 2) generate the ssh key for the h31 account
		$SUDO ssh-keygen -A
		# 3) tell user to run 'make dependencies', 'make install', and 'make provision' commands
		echo <<-EO4
*** We will now prepare this machine to ensure that it has needed software.
    This will cause items to be pulled from the internet and get installed.
    Afterward, the scripts we need to run the system will be added.
    Finally, we will enter an interactive provision step to define all the
    parameters needed to setup the software.  If you need to change any
    parameter afterward, login and do 'make -C /usr/local/src/patrios provision'
EO4
		if ! $DRY_RUN ; then
			#set -x
			ans=$(interactive "yes" "Ready to proceed")
			if [[ "$ans" == y* ]] ; then
				make dependencies && \
				make install && \
				make provision
			fi
		fi
		cat > $HOME/.motd <<-EO5

*** You may adjust configuration parameters as follows:
make -C /usr/local/src/patrios provision-video   - adjust video streaming parameters
make -C /usr/local/src/patrios provision-cameras - re-assign EO, Thermal and Rear cameras

EO5
		;;

	*)
		;;
esac

#if $DRY_RUN ; then
#	set +x
#fi
