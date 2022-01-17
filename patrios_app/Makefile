# Automation boilerplate

SHELL := /bin/bash
SUDO := $(shell test $${EUID} -ne 0 && echo "sudo")
# https://stackoverflow.com/questions/41302443/in-makefile-know-if-gnu-make-is-in-dry-run
DRY_RUN := $(if $(findstring n,$(firstword -$(MAKEFLAGS))),--dry-run)
DATE := $(shell date +%Y-%m-%d_%H%M)

# allow for generation of several static IP machines
VEHICLE := 8
HOST := 172.20.2.$(VEHICLE)
NETMASK := 16
.EXPORT_ALL_VARIABLES:

LOCAL=/usr/local
LOCAL_SCRIPTS=start-h31proxy.sh camera-switcher.sh ensure-network.sh temperature.sh
LIBSYSTEMD=/lib/systemd/system
#PLATFORM ?= $(shell python serial_number.py | cut -c1-4)
PLATFORM ?= NVID
SERVICES=camera-switcher.service ensure-network.service h31proxy.service temperature.service
# SYSCFG=/etc/systemd
SYSCFG=/usr/local/h31/conf
RULES=
UDEVRULES=/etc/udev/rules.d

.PHONY = clean debug dependencies disable enable git-cache install
.PHONY = postinstall provision provision-cameras provision-video
.PHONY = show-config test uninstall upgrade

default:
	@echo "Please choose an action:"
	@echo ""
	@echo "  postinstall: Do this once on a new clean system (may setup internet)"
	@echo "  upgrade: Do this once on a new clean system after postinstall (requires internet)"
	@echo "  dependencies: ensure all needed software is installed (requires internet)"
	@echo "  install: update programs and system scripts"
	@echo "  provision: interactively define the needed configurations (all of them)"
	@echo ""
	@echo "The above are issued in the order shown above.  postinstall is only done once."
	@echo "Once the system is setup, you can use these two shortcuts to modify video parameters:"
	@echo ""
	@echo "  provision-video: re-adjust video and audio streaming parameters"
	@echo "  provision-cameras: re-assign EO, Thermal and Rear cameras"
	@echo ""

$(LOCAL)/etc:
	@$(SUDO) mkdir -p $@

$(LOCAL)/etc/id_rsa: $(LOCAL)/etc
	@if [ ! -e $@ ] ; then \
		$(SUDO) ssh-keygen -t rsa -N "" -f $@ && \
		echo "*** On the Doodle Radio System->Administration page, ***" && \
		echo "***   1. enable ssh ***" && \
		echo "***   2. copy the content below to the ssh-keys section ***" && \
		$(SUDO) cat $@.pub ; \
	fi

$(LOCAL)/h31/camera-switcher.sh:
	$(SUDO) systemctl stop camera-switcher
	$(SUDO) install -Dm755 ./camera-switcher.sh $@

$(SYSCFG)/%.conf:
	PLATFORM=$(PLATFORM) ./provision.sh $@ $(DRY_RUN)

clean:
	/bin/true

debug:
	-$(SUDO) systemctl stop h31proxy
	@( x=$$(tail -n +2 $(SYSCFG)/mavproxy.conf) && set -a && eval $$x && set +a && set -x && \
	python3 h31proxy.py --master=$${DEVICE},$${BAUD} --out=$${PROTOCOL}:$${HOST}:$${PORT} --target-system=$${SYSID} --force-connected $$FLAGS ; \
	)

dependencies:
	@PLATFORM=$(PLATFORM) ./ensure-dependencies.sh $(DRY_RUN)
	@PLATFORM=$(PLATFORM) ./ensure-gst.sh $(DRY_RUN)
	@PLATFORM=$(PLATFORM) ./ensure-gstd.sh $(DRY_RUN)
	@PLATFORM=$(PLATFORM) ./ensure-camera-streamer.sh $(DRY_RUN)
	@./ensure-cockpit.sh
	@$(SUDO) apt-get install nano
	@$(SUDO) apt-get install apt-offline

disable:
	# https://lunar.computer/posts/nvidia-jetson-nano-headless/
	@for c in stop disable ; do $(SUDO) systemctl $$c gdm3 ; done
	$(SUDO) systemctl set-default multi-user.target

enable:
	# https://lunar.computer/posts/nvidia-jetson-nano-headless/
	$(SUDO) systemctl set-default graphical.target
	@for c in enable start ; do $(SUDO) systemctl $$c gdm3 ; done

git-cache:
	git config --global credential.helper "cache --timeout=5400"

install: git-cache
	@$(SUDO) rm -rf /usr/share/cockpit/general/ /usr/share/cockpit/video/ 
	@$(SUDO) mkdir /usr/share/cockpit/general/
	@$(SUDO) cp -rf ui/general/* /usr/share/cockpit/general/
	@$(SUDO) mkdir /usr/share/cockpit/video/
	@$(SUDO) cp -rf ui/video/* /usr/share/cockpit/video/
	@$(SUDO) cp -rf ui/branding-ubuntu/* /usr/share/cockpit/branding/ubuntu/
	@$(SUDO) cp -rf ui/static/* /usr/share/cockpit/static/	
	@$(SUDO) cp -rf ui/base1/* /usr/share/cockpit/base1/
	@[ -d $(LOCAL)/h31 ] || $(SUDO) mkdir $(LOCAL)/h31
	@$(SUDO) install -Dm755 cockpitScript.sh $(LOCAL)/h31/.
	@$(SUDO) chmod +x ensure-elp-driver.sh
	@./ensure-elp-driver.sh	
	@for s in $(RULES) ; do $(SUDO) install -Dm644 $${s%.*}.rules $(UDEVRULES)/$${s%.*}.rules ; done
	@if [ ! -z "$(RULES)" ] ; then $(SUDO) udevadm control --reload-rules && udevadm trigger ; fi
	@for s in $(LOCAL_SCRIPTS) ; do $(SUDO) install -Dm755 $${s} $(LOCAL)/h31/$${s} ; done
	@for c in stop disable ; do $(SUDO) systemctl $${c} $(SERVICES) ; done ; true
	@[ -d $(LOCAL)/h31/h31proxy ] || $(SUDO) mkdir $(LOCAL)/h31/h31proxy
	@$(SUDO) cp -a h31proxy/. $(LOCAL)/h31/h31proxy/
	@$(SUDO) chmod +x $(LOCAL)/h31/h31proxy/h31proxy.net
	@for s in $(SERVICES) ; do $(SUDO) install -Dm644 $${s%.*}.service $(LIBSYSTEMD)/$${s%.*}.service ; done
	@if [ ! -z "$(SERVICES)" ] ; then $(SUDO) systemctl daemon-reload ; fi
	@for s in $(SERVICES) ; do $(SUDO) systemctl enable $${s%.*} ; done

postinstall:
	./postinstall.sh $(DRY_RUN)

provision: $(LOCAL)/etc/id_rsa
	# NB: order is important in generating these files
	$(MAKE) --no-print-directory -B $(SYSCFG)/network.conf $(DRY_RUN)
	$(MAKE) --no-print-directory -B $(SYSCFG)/video-stream.conf $(DRY_RUN)
	$(MAKE) --no-print-directory -B $(SYSCFG)/mavproxy.conf $(DRY_RUN)
	@for s in $(SERVICES) ; do $(MAKE) --no-print-directory -B $(SYSCFG)/$${s%.*}.conf $(DRY_RUN) ; done
	$(MAKE) --no-print-directory -B $(LOCAL)/h31/camera-switcher.sh $(DRY_RUN)
	# NB: set the hostname according to the vehicle ID
	@( x=$$(tail -n +2 $(SYSCFG)/mavproxy.conf) && set -a && eval $$x && set +a && set -x && \
	echo "AMRK-$${SYSID}" > /tmp/$$.hostname && \
	$(SUDO) install -Dm644 /tmp/$$.hostname /etc/hostname && \
	$(SUDO) hostname AMRK-$${SYSID} ; \
	)
	# NB: this may cause a network reconfiguration
	@./ensure-network.sh $(DRY_RUN)
	$(SUDO) systemctl restart camera-switcher h31proxy

provision-cameras:
	$(MAKE) --no-print-directory -B $(SYSCFG)/camera-switcher.conf $(DRY_RUN)
	$(MAKE) --no-print-directory -B $(LOCAL)/h31/camera-switcher.sh $(DRY_RUN)
	$(SUDO) systemctl restart camera-switcher h31proxy

provision-video:
	$(MAKE) --no-print-directory -B $(SYSCFG)/video-stream.conf $(DRY_RUN)
	$(MAKE) --no-print-directory -B $(LOCAL)/h31/camera-switcher.sh $(DRY_RUN)
	$(SUDO) systemctl restart camera-switcher h31proxy

provision-mavproxy:
	$(MAKE) --no-print-directory -B $(SYSCFG)/mavproxy.conf $(DRY_RUN)
	$(SUDO) systemctl restart camera-switcher h31proxy

show-config:
	@for s in network.service video-stream.service $(SERVICES) ; do echo "*** $${s%.*}.conf ***" && $(SUDO) cat $(SYSCFG)/$${s%.*}.conf ; done
	@echo "*** cameras ***" && ls -al /dev/cam*

test:
	-@( gstd -k && gstd )
	gst-client pipeline_create testpipe videotestsrc name=vts ! autovideosink
	gst-client pipeline_play testpipe && sleep 5
	gst-client element_set testpipe vts pattern ball && sleep 5
	gst-client pipeline_stop testpipe
	gst-client pipeline_delete testpipe
	@gstd -k

uninstall:
	-@gstd -k
	-( cd $(LOCAL)/h31 && $(SUDO) rm $(LOCAL_SCRIPTS) )
	@-for c in stop disable ; do $(SUDO) systemctl $${c} $(SERVICES) ; done
	@for s in $(SERVICES) ; do $(SUDO) rm $(LIBSYSTEMD)/$${s%.*}.service ; done
	@if [ ! -z "$(SERVICES)" ] ; then $(SUDO) systemctl daemon-reload ; fi
	@for s in $(RULES) ; do $(SUDO) rm $(UDEVRULES)/$${s%.*}.rules ; done
	@if [ ! -z "$(RULES)" ] ; then $(SUDO) udevadm control --reload-rules && udevadm trigger ; fi

upgrade:
	$(SUDO) apt-get update
	$(SUDO) apt-get upgrade
