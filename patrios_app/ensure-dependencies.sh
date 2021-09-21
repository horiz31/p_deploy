#!/bin/bash
# usage:
#   ensure-dependencies.sh [--dry-run]
#
# Ensure that all application dependencies/modules needed are installed

DRY_RUN=false
SUDO=$(test ${EUID} -ne 0 && which sudo)

if [ "$1" == "--dry-run" ] ; then DRY_RUN=true && SUDO="echo ${SUDO}" ; fi

##PKGDEPS=sudo python3-netifaces v4l-utils
declare -A pkgdeps
pkgdeps[sudo]=true
pkgdeps[python3-netifaces]=true
pkgdeps[v4l-utils]=true

##PYTHONPKGS=
declare -A pydeps
#pydeps[xxx]=">=1.15.0"

# with dry-run, just go thru packages and return an error if some are missing
if $DRY_RUN ; then
	declare -A todo
	if [ -x apt ] ; then
		apt list --installed > /tmp/$$.pkgs 2>/dev/null	# NB: warning on stderr about unstable API
	else
		# TODO: figure out how to determine if something is installed in Yocto
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
		if [ "${#todo[@]}" -gt 0 ] ; then echo "Please run: apt-get install -y ${!todo[@]}" && exit 1 ; fi
	fi
	# python requirements
	echo "" > /tmp/$$.requirements
	for m in ${!pydeps[@]} ; do echo "$m${pydeps[$m]}" >> /tmp/$$.requirements ; done
	pip3 freeze -r /tmp/$$.requirements
	if pip3 freeze -r /tmp/$$.requirements ; then echo "Please run: pip3 install ${!pydeps[@]}" && exit 1 ; fi
	exit 0
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
if [ "${#pydeps[@]}" -gt 0 ] ; then
    if [ -z "$SUDO" ] ; then
	pip3 install ${!pydeps[@]}
    else
	$SUDO -H pip3 install ${!pydeps[@]}
    fi
fi
