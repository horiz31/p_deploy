#!/bin/bash
# usage:
#   ensure-camera-streamer.sh [--dry-run]
#
# Ensure that the camera-streamer module is installed

DRY_RUN=false
LOCAL=/usr/local
CAMERA_STREAMER=${LOCAL}/src/camera-streamer
UVDL=https://github.com/uvdl
SUDO=$(test ${EUID} -ne 0 && which sudo)

if [ "$1" == "--dry-run" ] ; then DRY_RUN=true && SUDO="echo ${SUDO}" ; fi
if [ -d "${CAMERA_STREAMER}" ] ; then
	( cd ${CAMERA_STREAMER} && echo -n "camera-streamer " && git log | head -1 )
	exit 0
fi

##PKGDEPS=uvcdynctrl v4l-utils python3-netifaces python3-pip
declare -A pkgdeps
pkgdeps[python3-netifaces]=true
pkgdeps[python3-pip]=true
pkgdeps[uvcdynctrl]=true
pkgdeps[v4l-utils]=true

# with dry-run, just go thru packages and return an error if some are missing
if $DRY_RUN ; then
	declare -A todo
	if [ -x $(which apt) ] ; then
		apt list --installed > /tmp/$$.pkgs 2>/dev/null	# NB: warning on stderr about unstable API
	else
		# TODO: figure out how to tell if something is installed in yocto
		touch /tmp/$$.pkgs
	fi
	for m in ${!pkgdeps[@]} ; do
		x=$(grep $m /tmp/$$.pkgs)
		if [ -z "$x" ] ; then
			echo "$m: missing"
			todo[$m]=true
		else
			true #&& echo "$x"
		fi
	done
	if [ -x $(which apt-get) ] ; then
		if [ "${#todo[@]}" -gt 0 ] ; then echo "Please run: apt-get install -y ${!todo[@]}" ; fi
		exit ${#todo[@]}
	else
		exit 0
	fi
fi
set -e
if [ "${#pkgdeps[@]}" -gt 0 ] ; then
    if [ -x $(which apt-get) ] ; then
	$SUDO apt-get install -y ${!pkgdeps[@]}
    else
        echo "Please run: apt-get install -y ${!pkgdeps[@]}"
	exit ${#pkgdeps[@]}
    fi
fi
if ! [ -d "${CAMERA_STREAMER}" ] ; then
	$SUDO mkdir -p $(dirname ${CAMERA_STREAMER}) && $SUDO chmod a+w $(dirname ${CAMERA_STREAMER})
	( cd $(dirname ${CAMERA_STREAMER}) && git clone ${UVDL}/$(basename ${CAMERA_STREAMER}).git -b master )
else
	( cd ${CAMERA_STREAMER} && git pull )
fi
# NB: we have satisfied the dependencies of camera-streamer for functions that we use with the above
#( cd ${CAMERA_STREAMER} && $SUDO make dependencies )
( cd ${CAMERA_STREAMER} && echo -n "camera-streamer " && git log | head -1 )
