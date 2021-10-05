#!/bin/bash
# usage:
#   provision.sh filename [--dry-run]
#
# Interactively create/update a systemd service configuration file
#
# TODO: figure out use of an encrypted filesystem to hold the configuration file
# https://www.linuxjournal.com/article/9400

CAMERA_STREAMER=/usr/local/src/camera-streamer
SUDO=$(test ${EUID} -ne 0 && which sudo)
SYSCFG=/usr/local/h31/conf
UDEV_RULESD=/etc/udev/rules.d

CONF=$1
shift
DEFAULTS=false
DRY_RUN=false
while (($#)) ; do
	if [ "$1" == "--dry-run" ] && ! $DRY_RUN ; then DRY_RUN=true ;
	elif [ "$1" == "--defaults" ] ; then DEFAULTS=true ;
	fi
	shift
done

function address_of {
	local result=$(ip addr show $1 | grep inet | grep -v inet6 | head -1 | sed -e 's/^[[:space:]]*//' | cut -f2 -d' ' | cut -f1 -d/)
	echo $result
}

function value_of {
	local result=$($SUDO grep $1 $CONF 2>/dev/null | cut -f2 -d=)
	if [ -z "$result" ] ; then result=$2 ; fi
	echo $result
}

# pull default provisioning items from the network.conf (generate it first)
function value_from_network {
	local result=$($SUDO grep $1 $(dirname $CONF)/network.conf 2>/dev/null | cut -f2 -d=)
	if [ -z "$result" ] ; then result=$2 ; fi
	echo $result
}

function interactive {
	local result
	read -p "${2}? ($1) " result
	if [ -z "$result" ] ; then result=$1 ; elif [ "$result" == "*" ] ; then result="" ; fi
	echo $result
}

function contains {
	local result=no
	#if [[ " $2 " =~ " $1 " ]] ; then result=yes ; fi
	if [[ $2 == *"$1"* ]] ; then result=yes ; fi
	echo $result
}

# configuration values used in this script
declare -A config
config[iface]=$(value_from_network IFACE wlan0)

case "$(basename $CONF)" in
	mavproxy.conf)
		# TODO: mavproxy --out needs udp or udpbcast (or udpmcast?) based on HOST  (see mavproxy.service)
		BAUD=$(value_of BAUD 115200)
		DEVICE=$(value_of DEVICE /dev/ttyTHS1)
		FLAGS=($(value_of FLAGS ""))
		_FLOW=$(contains "--rtscts" "${FLAGS[@]}")
		_DEBUG=$(contains "--debug" "${FLAGS[@]}")
		IFACE=$(value_of IFACE ${config[iface]})
		HOST=$(value_of HOST 224.10.10.10)  # $(echo $(address_of ${IFACE}) | cut -f1,2 -d.).255.255)
		PORT=$(value_of PORT 14550)
		ATAK_HOST=$(value_of ATAK_HOST 239.2.3.1)
		ATAK_PORT=$(value_of ATAK_PORT 6969)
		ATAK_PERIOD=$(value_of ATAK_PERIOD 5)
		SYSID=$(value_of SYSID $(echo $(address_of ${IFACE}) | cut -f4 -d.))

		if ! $DEFAULTS ; then
			#IFACE=$(interactive "$IFACE" "UDP Interface for telemetry")
			HOST=$(interactive "$HOST" "UDP IPv4 for telemetry")
			PORT=$(interactive "$PORT" "UDP PORT for telemetry")
			DEVICE=$(interactive "$DEVICE" "Serial Device for flight controller")
			BAUD=$(interactive "$BAUD" "Baud rate for flight controller")
			_FLOW=$(interactive "$_FLOW" "RTS/CTS Flow Control")
			_DEBUG=$(interactive "$_DEBUG" "Verbose Operation")
			ATAK_HOST=$(interactive "$ATAK_HOST" "ATAK_HOST, Multicast address for ATAK CoT messages")	
			ATAK_PORT=$(interactive "$ATAK_PORT" "ATAK_PORT, Port for where to send the ATAK CoT messages")	
			ATAK_PERIOD=$(interactive "$ATAK_PERIOD" "ATAK_PERIOD, Number of seconds between each ATAK CoT message")	
			SYSID=$(interactive "$SYSID" "System ID of the flight controller")
			
		fi
		# Different systems have mavproxy installed in various places
		MAVPROXY=/usr/local/h31/h31proxy.py
		# mavproxy wants LOCALAPPDATA to be valid
		LOCALAPPDATA='/tmp'
		# FLAGS must keep the --rtscts as that is what mavproxy uses
		if [ "${_FLOW}" == "on" ] || [[ ${_FLOW} == y* ]] ; then
			if [[ ! " ${FLAGS[@]} " =~ " --rtscts " ]] ; then FLAGS=(--rtscts) ; fi
		elif [ "${_DEBUG}" == "on" ] || [[ ${_DEBUG} == y* ]] ; then
			FLAGS=(--debug)
		else
			# BUT! FLAGS cannot be empty for systemd, so we pick something benign
			FLAGS=(--nodtr)
		fi
		# Need to track what type of --out device to use, based on HOST (udp, udpbcast)
		# NB: mavproxy.py only intrprets udp or udpbcast.  h31proxy.py uses ipv4 to infer the protocol, but tolerates both.
		# NB: mavproxy.py udpbcast does not work as of 2020-05-15 or so.
		if [[ $HOST == *255* ]] ; then PROTOCOL=udpbcast ; else PROTOCOL=udp ; fi
		# https://forums.developer.nvidia.com/t/jetson-nano-how-to-use-uart-on-ttyths1/82037
		if ! $DRY_RUN ; then
			#set -x
			if [ "${DEVICE}" == "/dev/ttyTHS1" ] ; then
				$SUDO systemctl stop nvgetty && \
				$SUDO systemctl disable nvgetty
			fi
			if [ -c ${DEVICE} ] ; then
				$SUDO chown root:dialout ${DEVICE} && \
				$SUDO chmod 660 ${DEVICE}
				# https://stackoverflow.com/questions/41266001/screen-dev-ttyusb0-with-different-options-such-as-databit-parity-etc/52391586
				opts=(cs8 -parenb -cstopb)	# 8N1
				if [[ " ${FLAGS[@]} " =~ " --rtscts " ]] ; then opts+=(crtscts) ; fi
				stty -F ${DEVICE} "${opts[@]}"
			fi
			#set +x
		fi
		echo "[Service]" > /tmp/$$.env && \
		echo "BAUD=${BAUD}" >> /tmp/$$.env && \
		echo "DEVICE=${DEVICE}" >> /tmp/$$.env && \
		echo "FLAGS=${FLAGS[@]}" >> /tmp/$$.env && \
		echo "IFACE=${IFACE}" >> /tmp/$$.env && \
		echo "PROTOCOL=${PROTOCOL}" >> /tmp/$$.env && \
		echo "HOST=${HOST}" >> /tmp/$$.env && \
		echo "LOCALAPPDATA=${LOCALAPPDATA}" >> /tmp/$$.env && \
		echo "MAVPROXY=${MAVPROXY}" >> /tmp/$$.env && \
		echo "PORT=${PORT}" >> /tmp/$$.env && \
		echo "ATAK_HOST=${ATAK_HOST}" >> /tmp/$$.env && \
		echo "ATAK_PORT=${ATAK_PORT}" >> /tmp/$$.env && \
		echo "ATAK_PERIOD=${ATAK_PERIOD}" >> /tmp/$$.env && \
		echo "SYSID=${SYSID}" >> /tmp/$$.env
		;;

	camera-switcher.conf)
		config[cam1]=$(value_of CAM1 "a")
		config[cam2]=$(value_of CAM2 "a")
		config[cam3]=$(value_of CAM3 "a")
		if ! $DEFAULTS ; then
			lsusb && echo ""
			for d in /dev/video[0-9]* ; do
				echo "*** $d ***"
				if udevadm info -a -n $d | grep ATTRS | grep -E 'manufacturer|product|devpath' | head -3 ; then
					udevadm info -a -n $d | grep ATTRS | grep -E 'manufacturer|product' | head -2
					v4l2-ctl -d $d --list-formats
					echo ""
				fi
			done
			config[cam1]=$(interactive "${config[cam1]}" "Select n (/dev/video*) for camera 1 (a automatic, x disables)")
			config[cam2]=$(interactive "${config[cam2]}" "Select n (/dev/video*) for camera 2 (a automatic, x disables)")
			config[cam3]=$(interactive "${config[cam3]}" "Select n (/dev/video*) for camera 3 (a automatic, x disables)")
			# generate udev rules for selected cameras
			touch /tmp/$$.rule
			for n in 1 2 3 ; do
				# https://wiki.archlinux.org/index.php/Udev#Video_device
				if [ "${config[cam${n}]}" == "x" ] ; then
					echo "*** cam${n} skipped ***"
				elif [ "${config[cam${n}]}" == "a" ] ; then
					echo "*** cam${n} automatic ***"
					if [ "$n" == "1" ] ; then   # 32e4:0001
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"32e4\", ATTRS{idProduct}==\"0001\", ATTR{index}==\"0\", SYMLINK+=\"cam${n}\"" >> /tmp/$$.rule
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"32e4\", ATTRS{idProduct}==\"0001\", ATTR{index}==\"1\", SYMLINK+=\"stream${n}\"" >> /tmp/$$.rule
					elif [ "$n" == "3" ] ; then # 32e4:0002
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"32e4\", ATTRS{idProduct}==\"0002\", ATTR{index}==\"0\", SYMLINK+=\"cam${n}\"" >> /tmp/$$.rule
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"32e4\", ATTRS{idProduct}==\"0002\", ATTR{index}==\"1\", SYMLINK+=\"stream${n}\"" >> /tmp/$$.rule
					else # n == 2, 09cb:4007
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"09cb\", ATTRS{idProduct}==\"4007\", ATTR{index}==\"0\", SYMLINK+=\"cam${n}\"" >> /tmp/$$.rule
						# NB: FLIR does not have an h.264 output endpoint
					fi
				elif [ ! -z "${config[cam${n}]}" ] ; then
					ok=true
					udevadm info -a -n /dev/video${config[cam${n}]} | grep ATTR > /tmp/camera${n}.$$
					for kw in devpath idProduct idVendor ; do
						config[$kw]=$(grep $kw /tmp/camera${n}.$$ | head -1 | cut -f2 -d\")
						if [ -z "${config[$kw]}" ] ; then ok=false ; fi
					done
					if $ok ; then
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"${config[idVendor]}\", ATTRS{idProduct}==\"${config[idProduct]}\", ATTRS{devpath}==\"${config[devpath]}\", ATTR{index}==\"0\", SYMLINK+=\"cam${n}\"" >> /tmp/$$.rule
						echo "SUBSYSTEM==\"video4linux\", ATTRS{idVendor}==\"${config[idVendor]}\", ATTRS{idProduct}==\"${config[idProduct]}\", ATTRS{devpath}==\"${config[devpath]}\", ATTR{index}==\"1\", SYMLINK+=\"stream${n}\"" >> /tmp/$$.rule
					else
						echo "*** /dev/video${config[cam${n}]} not configured for cam${n} ***"
					fi
				fi
			done
			if $DRY_RUN ; then
				echo ${UDEV_RULESD}/83-webcam.rules && cat /tmp/$$.rule && echo ""
			else
				set -x
				$SUDO install -Dm644 /tmp/$$.rule ${UDEV_RULESD}/83-webcam.rules
				$SUDO udevadm control --reload-rules && $SUDO udevadm trigger
				set +x
			fi
		fi
		echo "[Service]" > /tmp/$$.env && \
		echo "CAM1=${config[cam1]}" >> /tmp/$$.env && \
		echo "CAM2=${config[cam2]}" >> /tmp/$$.env && \
		echo "CAM3=${config[cam3]}" >> /tmp/$$.env && \
		echo "CONF=$(dirname $CONF)/video-stream.conf" >> /tmp/$$.env
		;;

	# NB: the Makefile uses a static file copy due to the use of interpipe for fast camera switching
	# So this code is not executed at the moment.
	camera-switcher.sh)
		# https://unix.stackexchange.com/questions/79068/how-to-export-variables-that-are-set-all-at-once
		# set -a && source ${SYSCFG}/video-stream.conf && set +a
		x=$(tail -n +2 ${SYSCFG}/video-stream.conf) && set -a && eval $x && set +a
		# now we have the environment settings for video
		p1=$(PLATFORM=${PLATFORM} VIDEO_DEVICE=/dev/cam1 FLAGS=debug,smpte,${FLAGS} ${CAMERA_STREAMER}/video-stream.sh 2>/dev/null)
		p2=$(PLATFORM=${PLATFORM} VIDEO_DEVICE=/dev/cam2 FLAGS=debug,smpte,${FLAGS} ${CAMERA_STREAMER}/video-stream.sh 2>/dev/null)
		p3=$(PLATFORM=${PLATFORM} VIDEO_DEVICE=/dev/cam3 FLAGS=debug,smpte,${FLAGS} ${CAMERA_STREAMER}/video-stream.sh 2>/dev/null)
		if [ -z "$p1" ] ; then echo "*** Did not produce cam1 pipeline - STOP" ; exit 1 ; fi
		if [ -z "$p2" ] ; then echo "*** Did not produce cam2 pipeline - STOP" ; exit 1 ; fi
		if [ -z "$p3" ] ; then echo "*** Did not produce cam3 pipeline - STOP" ; exit 1 ; fi
		# now we have the 3 pipelines that should be executed
		echo "#!/bin/bash" > /tmp/$$.env && \
		echo "# ensure previous pipelines are cancelled and cleared" >> /tmp/$$.env && \
		echo "gstd -f /var/run -l /dev/null -d /dev/null -k" >> /tmp/$$.env && \
		echo "gstd -f /var/run -l /var/run/camera-switcher/gstd.log -d /var/run/camera-switcher/gst.log" >> /tmp/$$.env && \
		echo "gst-client pipeline_create cam1 $p1" >> /tmp/$$.env && \
		echo "gst-client pipeline_create cam2 $p2" >> /tmp/$$.env && \
		echo "gst-client pipeline_create cam3 $p3" >> /tmp/$$.env && \
		echo "# start cam1 by default" >> /tmp/$$.env && \
		echo "gst-client pipeline_play cam1" >> /tmp/$$.env && \
		echo "" >> /tmp/$$.env
		;;

	audio-streamer.conf)
		IFACE=$(value_of IFACE ${config[iface]})
		_NAME=$(value_of NAME "Camera_1") ; NAME=${_NAME//\"}
		_MIC=$(value_of MIC "") ; MIC=${_MIC//\"}
		#_XY=$(echo $(address_of ${IFACE}) | cut -f3,4 -d.) ; if [ -z "$_XY" ] ; then _XY='1.1' ; fi
		#HOST=$(value_of HOST 224.1.$_XY)
		#PORT=$(value_of PORT 5601)
		HOST=127.0.0.1
		PORT=6000
		if ! $DEFAULTS ; then
			arecord -l | grep 'card.*device'
			NAME=$(interactive "$NAME" "Audio device name")
			# TODO: here is where you can pick up the device name and translate it to the DEV (hw:x,y) format
			#IFACE=$(interactive "$IFACE" "RJ45 Network device for audio")
			#HOST=$(interactive "$HOST" "RJ45 Network IPv4 destination for audio")
			#PORT=$(interactive "$PORT" "UDP PORT for audio")
		fi
		echo "[Service]" > /tmp/$$.env && \
		echo "IFACE=${IFACE}" >> /tmp/$$.env && \
		echo "HOST=${HOST}" >> /tmp/$$.env && \
		echo "MIC=\"${MIC//\"}\"" >> /tmp/$$.env && \
		echo "NAME=\"${NAME//\"}\"" >> /tmp/$$.env && \
		echo "PORT=${PORT}" >> /tmp/$$.env
		;;

	audio-streamer.sh)
		# https://unix.stackexchange.com/questions/79068/how-to-export-variables-that-are-set-all-at-once
		x=$(tail -n +2 ${SYSCFG}/audio-streamer.conf) && set -a && eval $x && set +a
		# now we have the environment settings for audio
		p1=$(PLATFORM=${PLATFORM} IFACE=${IFACE} HOST=${HOST} NAME=\"${NAME}\" PORT=${PORT} DEBUG=true ./audio-stream.sh 2>/dev/null)
		if [ -z "$p1" ] ; then echo "*** Did not produce audio pipeline - STOP" ; exit 1 ; fi
		echo "#!/bin/bash" > /tmp/$$.env && \
		echo "# NB: expects camera-switcher service to have restarted gstd" >> /tmp/$$.env && \
		echo "gst-client pipeline_create mic1 $p1" >> /tmp/$$.env && \
		echo "gst-client pipeline_play mic1" >> /tmp/$$.env && \
		echo "" >> /tmp/$$.env
		;;

	network.conf)
		IFACE=$(value_of IFACE eth0)
		HOST=$(value_of HOST $(address_of ${IFACE}))
		GATEWAY=$(value_of GATEWAY 172.20.100.100)
		NETMASK=$(value_of NETMASK 16)
		if ! $DEFAULTS ; then
			IFACE=$(interactive "$IFACE" "RJ45 Network Interface")
			HOST=$(interactive "$HOST" "IPv4 for RJ45 Network")
			GATEWAY=$(interactive "$GATEWAY" "IPv4 gateway for RJ45 Network")
			NETMASK=$(interactive "$NETMASK" "CDIR/netmask for RJ45 Network")
		fi
		echo "[Service]" > /tmp/$$.env && \
		echo "IFACE=${IFACE}" >> /tmp/$$.env && \
		echo "HOST=${HOST}" >> /tmp/$$.env && \
		echo "GATEWAY=${GATEWAY}" >> /tmp/$$.env && \
		echo "NETMASK=${NETMASK}" >> /tmp/$$.env
		;;

	video-stream.conf)
		UDP_IFACE=$(value_of UDP_IFACE ${config[iface]})
		_XY=$(echo $(address_of ${UDP_IFACE}) | cut -f3,4 -d.) ; if [ -z "$_XY" ] ; then _XY='1.1' ; fi
		UDP_HOST=$(value_of UDP_HOST 224.10.$_XY)
		UDP_PORT=$(value_of UDP_PORT 5600)		
		UDP_TTL=10
		WIDTH=$(value_of WIDTH 1280)
		HEIGHT=$(value_of HEIGHT 720)
		FPS=$(value_of FPS 15)
		VIDEO_BITRATE=$(value_of VIDEO_BITRATE 2000)
		GOP=$(value_of GOP 15)
		IDR=$(value_of IDR 15)
		SPS=$(value_of SPS -1)
		QP=$(value_of QP 10)
		SS=$(value_of SS 0)
		IREF=$(value_of IREF 0)
		URL=$(value_of URL udp)
		AUDIO_BITRATE=$(value_of AUDIO_BITRATE 128)
		AUDIO_PORT=$(value_of AUDIO_PORT 5601)
		ATAK_IFACE=$(value_of ATAK_IFACE ${config[iface]})
		ATAK_HOST=$(value_of ATAK_HOST 239.10.$_XY)
		ATAK_PORT=$(value_of ATAK_PORT 5600)
		ATAK_BITRATE=$(value_of ATAK_BITRATE 500)
		if ! $DEFAULTS ; then
			UDP_IFACE=$(interactive "$UDP_IFACE" "RJ45 Network device for video")
			UDP_HOST=$(interactive "$UDP_HOST" "RJ45 Network IPv4 destination for video")
			UDP_PORT=$(interactive "$UDP_PORT" "UDP PORT for video")
			WIDTH=$(interactive "$WIDTH" "Video stream width")
			HEIGHT=$(interactive "$HEIGHT" "Video stream height")
			FPS=$(interactive "$FPS" "Video stream frames/sec")
			VIDEO_BITRATE=$(interactive "$VIDEO_BITRATE" "Video stream bitrate in kbps/sec")
			#GOP=$(interactive "$GOP" "Group of Pictures in frames")
			IDR=$(interactive "$IDR" "Keyframe interval in frames")
			AUDIO_BITRATE=$(interactive "$AUDIO_BITRATE" "Audio stream bitrate in kbps/sec")
			AUDIO_PORT=$(interactive "$AUDIO_PORT" "UDP PORT for audio")
			ATAK_IFACE=$(interactive "$ATAK_IFACE" "RJ45 Network device for ATAK video")
			ATAK_HOST=$(interactive "$ATAK_HOST" "RJ45 Network IPv4 destination for ATAK video")
			ATAK_PORT=$(interactive "$ATAK_PORT" "UDP PORT for ATAK video")
			ATAK_BITRATE=$(interactive "$ATAK_BITRATE" "ATAK video stream bitrate in kbps/sec")
			GOP=$IDR
			#SPS=$(interactive "$SPS" "SPS and PPS Insertion Interval in sec (-1=use IDR)")
			# macroblocks are 16x16 pixel blocks
			#QP=$(interactive "$QP" "Quantization Parameter [0,51] (used with VBR)")
			#SS=$(interactive "$SS" "Slice Size (0 = unlimited, <0 in macroblock, >0 in bits)")
			#IREF=$(interactive "$IREF" "Macroblocks to encode as intra MB")
			#FLAGS=$(interactive "$FLAGS" "Video stream flags")
		fi
		echo "[Service]" > /tmp/$$.env && \
		echo "PLATFORM=${PLATFORM}" >> /tmp/$$.env && \
		echo "UDP_IFACE=${UDP_IFACE}" >> /tmp/$$.env && \
		echo "UDP_HOST=${UDP_HOST}" >> /tmp/$$.env && \
		echo "UDP_PORT=${UDP_PORT}" >> /tmp/$$.env && \
		echo "UDP_TTL=${UDP_TTL}" >> /tmp/$$.env && \
		echo "WIDTH=${WIDTH}" >> /tmp/$$.env && \
		echo "HEIGHT=${HEIGHT}" >> /tmp/$$.env && \
		echo "FPS=${FPS}" >> /tmp/$$.env && \
		echo "VIDEO_BITRATE=${VIDEO_BITRATE}" >> /tmp/$$.env && \
		echo "GOP=${GOP}" >> /tmp/$$.env && \
		echo "IDR=${IDR}" >> /tmp/$$.env && \
		echo "SPS=${SPS}" >> /tmp/$$.env && \
		echo "QP=${QP}" >> /tmp/$$.env && \
		echo "SS=${SS}" >> /tmp/$$.env && \
		echo "IREF=${IREF}" >> /tmp/$$.env && \
		echo "AUDIO_BITRATE=${AUDIO_BITRATE}" >> /tmp/$$.env && \
		echo "AUDIO_PORT=${AUDIO_PORT}" >> /tmp/$$.env && \
		echo "ATAK_IFACE=${ATAK_IFACE}" >> /tmp/$$.env && \
		echo "ATAK_HOST=${ATAK_HOST}" >> /tmp/$$.env && \
		echo "ATAK_PORT=${ATAK_PORT}" >> /tmp/$$.env && \
		echo "ATAK_BITRATE=${ATAK_BITRATE}" >> /tmp/$$.env && \
		echo "URL=${URL}" >> /tmp/$$.env
		;;

	*)
		# preserve contents or generate a viable empty configuration
		echo "[Service]" > /tmp/$$.env
		;;
esac

if $DRY_RUN ; then
	echo $CONF && cat /tmp/$$.env && echo ""
elif [[ $(basename $CONF) == *.sh ]] ; then
	$SUDO install -Dm755 /tmp/$$.env $CONF
else
	$SUDO install -Dm644 /tmp/$$.env $CONF
fi
rm /tmp/$$.env
