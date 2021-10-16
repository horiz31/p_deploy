#!/bin/bash

LOCAL=/usr/local
ELP=${LOCAL}/src/ELP_H264_UVC/Linux_UVC_TestAP/
FORMAT=I420
SCALING=false
RED=4294901760  ## FFFF0000
GRN=4278255360  ## FF00FF00
BLU=4278190335  ## FF0000FF
# NB: still need a scaler for use with the BOSON
boson_width=640
boson_height=512
boson_fps=30
boson_format=I420
scaler="videoscale method=bilinear name=scale"

export
set +x
qmst=$(( 2010000000 / $FPS )) # two frames, rounded up to nearest ms
kbps=$(( $VIDEO_BITRATE ))
camera264bps=$(( 5 * 1000 * 1000 )) #pull 5Mbps from camera, which will be 265 encoded. This ensures higher quality while keeping usb data in check
bps=$(( $kbps * 1000 )) # the bitrate used for final 264 encoding
atak_bps=$(($ATAK_BITRATE * 1000)) # atak bitrate
audio_bps=$(( $AUDIO_BITRATE * 1000 )) # audio bitrate
gstd -f /var/run -l /dev/null -d /dev/null -k
gstd -f /var/run -l /var/run/camera-switcher/gstd.log -d /var/run/camera-switcher/gst.log

264encoder="omxh264enc bitrate=$bps iframeinterval=$GOP"
parser="h264parse config-interval=1"
payloader="rtph264pay config-interval=1 pt=96"
xvideo="x-h264"

# if host is multicast, then append extra
if [[ "$UDP_HOST" =~ ^[2][2-3][4-9].* ]]; then
    extra_los="multicast-iface=${UDP_IFACE} auto-multicast=true ttl=10"
fi
if [[ "$ATAK_HOST" =~ ^[2][2-3][4-9].* ]]; then
    extra_atak="multicast-iface=${ATAK_IFACE} auto-multicast=true ttl=10"
fi

for c in 1 3 ; do
    # Front camera is /dev/cam1, /dev/stream1 producing 'cam1'
    # Rear camera is /dev/cam3, /dev/stream3 producing 'cam3'
    # H.264 stream no SCALING (pull desired resolution and frame rate directly off)
    if [ -c /dev/stream${c} ] ; then
        echo "Setting up stream ${c}"
        ${ELP}/H264_UVC_TestAP /dev/stream${c} --xuset-br $camera264bps
        ${ELP}/H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create src${c} v4l2src device=/dev/stream${c} ! "video/x-h264,stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # Either no camera or invalid FLAGS
    else
        echo "Warning: Camera ${c} not found"
        if [ -c /dev/cam${c} ] ; then pattern=spokes ; else pattern=solid-color ; fi
        if [ "${c}" == "1" ] ; then color=$RED ; else color=$BLU ; fi
        gst-client pipeline_create src${c} videotestsrc is-live=true pattern=$pattern foreground-color=$color ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${264encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    fi
    # Front/Rear Camera Loop
done
# Thermal camera is raw only (so use /dev/cam2)
if [ -c /dev/cam2 ] ; then
    echo "Setting up Stream 2 (Thermal)"
    gst-client pipeline_create src2 v4l2src device=/dev/cam2 io-mode=mmap ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${boson_fps}/1" ! videorate max-rate=$FPS skip-to-first=true ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${FPS}/1" ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! omxh264enc bitrate=2000000 iframeinterval=$GOP ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
else
    echo "Warning: Steam 2 (Thermal) camera not found"
    gst-client pipeline_create src2 videotestsrc is-live=true pattern=solid-color foreground-color=$GRN ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${264encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
fi

# create the atak stream (264)
gst-client pipeline_create atak interpipesrc name=atak_switch listen-to=cam1 ! h264parse ! omxh264dec disable-dpb=true ! queue ! omxh264enc bitrate=$atak_bps ! h264parse ! mpegtsmux ! rtpmp2tpay ! udpsink sync=false host=${ATAK_HOST} port=${ATAK_PORT} ${extra_atak}

# create the primary output pipeline (265)
gst-client pipeline_create stream1 interpipesrc name=switch listen-to=cam1 block=true is-live=true allow-renegotiation=true stream-sync=compensate-ts ! h264parse ! omxh264dec disable-dpb=true ! queue ! omxh265enc bitrate=$bps ! rtph265pay config-interval=1 pt=96 ! udpsink sync=false host=${UDP_HOST} port=${UDP_PORT} ${extra_los}

# bug in interpipe requires RX to start first; or use stream-sync=2
if [[ $VIDEO_BITRATE != "0" ]] ; then
        gst-client pipeline_play stream1
else
        gst-client pipeline_stop stream1
fi

if [[ $ATAK_BITRATE != "0" ]] ; then
        gst-client pipeline_play atak
else
        gst-client pipeline_stop atak
fi

# start pipelines streaming
gst-client pipeline_play src1
gst-client pipeline_play src2
gst-client pipeline_play src3
# NB: may need a gratuitous switch
gst-client element_set stream1 switch listen-to cam1
gst-client element_set atak atak_switch listen-to cam1

#audio, pick the second H264 source (see tail -1)
p=$(arecord -l | grep 'card.*device' | grep 'H264')
if [[ -n $p ]] ; then
        c=$(echo "$p" | tail -1 | cut -f1 -d, | cut -f1 -d: | cut -f2 -d' ')
        d=$(echo "$p" | tail -1 | cut -f2 -d, | cut -f1 -d: | cut -f3 -d' ')
        gst-client pipeline_create mic alsasrc device="hw:${c},${d}" ! "audio/x-raw,format=(string)S16LE,rate=(int)44100,channels=(int)1" ! interpipesink name=mic
        gst-client pipeline_create audio_los interpipesrc listen-to=mic is-live=true block=true ! voaacenc bitrate=$audio_bps ! aacparse ! rtpmp4apay pt=96 ! udpsink sync=false host=${UDP_HOST} port=${AUDIO_PORT} ${extra_los}
        # start the audio pipeline
        if [[ $AUDIO_BITRATE != "0" ]] ; then
                gst-client pipeline_play audio_los
                # start the mic pipeline last
                gst-client pipeline_play mic
        else
                gst-client pipeline_stop audio_los
                # start the mic pipeline last
                gst-client pipeline_stop mic
        fi
else
        echo "No suitable H264 camera audio device found"
fi


