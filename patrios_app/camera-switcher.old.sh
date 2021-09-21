#!/bin/bash
# NB: environment variables from /etc/systemd/video-stream.conf are expected (see camera-switcher.service)
# ensure previous pipelines are cancelled and cleared
gstd -f /var/run -l /dev/null -d /dev/null -k
gstd -f /var/run -l /var/run/camera-switcher/gstd.log -d /var/run/camera-switcher/gst.log
#
# Original Nano
#
if [[ " ${FLAGS[@]} " =~ "legacy" ]] ; then
gst-client pipeline_create src1  v4l2src device=/dev/cam1 io-mode=mmap ! "video/x-raw,format=(string)YUY2,width=(int)640,height=(int)360,framerate=(fraction)15/1" ! videoconvert name=input-format ! "video/x-raw,format=(string)I420,width=(int)640,height=(int)360,framerate=(fraction)15/1" ! videoscale method=bilinear name=input-scale ! "video/x-raw,format=(string)I420,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)15/1" ! interpipesink name=cam1
gst-client pipeline_create src2  v4l2src device=/dev/cam2 io-mode=mmap ! "video/x-raw,format=(string)I420,width=(int)640,height=(int)512,framerate=(fraction)30/1" ! videorate name=input-rate max-rate=15 skip-to-first=true ! "video/x-raw,format=(string)I420,width=(int)640,height=(int)512,framerate=(fraction)15/1" ! videoscale method=bilinear name=input-scale ! "video/x-raw,format=(string)I420,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)15/1" ! interpipesink name=cam2
gst-client pipeline_create src3  v4l2src device=/dev/cam3 io-mode=mmap ! "video/x-raw,format=(string)YUY2,width=(int)640,height=(int)360,framerate=(fraction)15/1" ! videoconvert name=input-format ! "video/x-raw,format=(string)I420,width=(int)640,height=(int)360,framerate=(fraction)15/1" ! videoscale method=bilinear name=input-scale ! "video/x-raw,format=(string)I420,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)15/1" ! interpipesink name=cam3
gst-client pipeline_create stream1 interpipesrc name=switch listen-to=cam1 is-live=true allow-renegotiation=true stream-sync=compensate-ts ! "video/x-raw,format=(string)I420,framerate=(fraction)15/1,width=(int)$WIDTH,height=(int)$HEIGHT" ! omxh265enc bitrate=$(( $VIDEO_BITRATE * 1000 )) iframeinterval=60 ! "video/x-h265,stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)15/1" ! h265parse ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=67000000 min-threshold-buffers=1 leaky=upstream ! rtph265pay config-interval=10 pt=96 ! mux.sink_0 rtpmux name=mux ! udpsink name=output host=127.0.0.1 port=$UDP_PORT ttl=10
# start source pipelines streaming
gst-client pipeline_play stream1
gst-client pipeline_play src1
gst-client pipeline_play src2
gst-client pipeline_play src3
# NB: may need a gratuitous switch
gst-client element_set stream1 switch listen-to cam1
exit 0
fi
FORMAT=I420
SCALING=false
RED=4294901760	## FFFF0000
GRN=4278255360	## FF00FF00
BLU=4278190335	## FF0000FF
# NB: still need a scaler for use with the BOSON
boson_width=640
boson_height=512
boson_fps=30
boson_format=I420
scaler="videoscale method=bilinear name=scale"
if [[ " ${FLAGS[@]} " =~ "scale" ]] ; then SCALING=true ; fi
# parameters based on frame rate
export
set +x
qmst=$(( 2010000000 / $FPS )) # two frames, rounded up to nearest ms
kbps=$(( $VIDEO_BITRATE ))
bps=$(( $kbps * 1000 ))
camera_bps=$(( 16 * 1000 * 1000 ))  # camera bitrate to use for 'h264,native,(h)scale'
camera_mjb=$(( 80 * 1000 * 1000 ))  # camera bitrate to use for 'h264,mjpg'
# select encoder
if [[ " ${FLAGS[@]} " =~ "h264" ]] ; then
	encoder="omxh264enc name=encoder bitrate=$bps iframeinterval=$GOP"
	parser="h264parse config-interval=$SPS"
	payloader="rtph264pay config-interval=$SPS pt=96"
	xvideo="x-h264"
elif [[ " ${FLAGS[@]} " =~ "h265" ]] ; then
	encoder="omxh265enc name=encoder bitrate=$bps iframeinterval=$GOP"
	parser="h265parse config-interval=$SPS"
	payloader="rtph265pay config-interval=$SPS pt=96"
	xvideo="x-h265"
fi
#
# h264,native,interpipe: switch between h.264 encoded streams with control over output destination
#
if [[ " ${FLAGS[@]} " =~ "interpipe" ]] && [[ " ${FLAGS[@]} " =~ "native" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] && ! ${SCALING} ; then
  for c in 1 3 ; do
    # Front camera is /dev/cam1, /dev/stream1 producing 'cam1'
    # Rear camera is /dev/cam3, /dev/stream3 producing 'cam3'
    # H.264 stream no SCALING (pull desired resolution and frame rate directly off)
    if [ -c /dev/stream${c} ] && [[ " ${FLAGS[@]} " =~ "native" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] ; then
        H264_UVC_TestAP /dev/stream${c} --xuset-br $bps
        H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create src${c} v4l2src device=/dev/stream${c} io-mode=mmap ! "video/x-h264,stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # Either no camera or invalid FLAGS
    else
        if [ -c /dev/cam${c} ] ; then pattern=spokes ; else pattern=solid-color ; fi
        if [ "${c}" == "1" ] ; then color=$RED ; else color=$BLU ; fi
        gst-client pipeline_create src${c} videotestsrc is-live=true pattern=$pattern foreground-color=$color ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    fi
  # Front/Rear Camera Loop
  done
    # Thermal camera is raw only (so use /dev/cam2)
    if [ -c /dev/cam2 ] ; then
        gst-client pipeline_create src2 v4l2src device=/dev/cam2 io-mode=mmap ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${boson_fps}/1" ! videorate max-rate=$FPS skip-to-first=true ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${FPS}/1" ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
    else
        gst-client pipeline_create src2 videotestsrc is-live=true pattern=solid-color foreground-color=$GRN ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
    fi
    # one output pipeline
    gst-client pipeline_create stream1 interpipesrc name=switch listen-to=cam1 is-live=true allow-renegotiation=true stream-sync=compensate-ts ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL
    # bug in interpipe requires RX to start first; or use stream-sync=2
    gst-client pipeline_play stream1
    # start pipelines streaming
    gst-client pipeline_play src1
    gst-client pipeline_play src2
    gst-client pipeline_play src3
    # NB: may need a gratuitous switch
    gst-client element_set stream1 switch listen-to cam1
#
# interpipe: switch between raw streams with single encoder and control over output destination
#
elif [[ " ${FLAGS[@]} " =~ "interpipe" ]] ; then
  for c in 1 3 ; do
    # Front camera is /dev/cam1, /dev/stream1 producing 'cam1'
    # Rear camera is /dev/cam3, /dev/stream3 producing 'cam3'
    # H.264 stream w/SCALING (pull camera at high res, then transcode to desired resolution)
    if [ -c /dev/stream${c} ] && [[ " ${FLAGS[@]} " =~ "native" ]] && ${SCALING} ; then
        H264_UVC_TestAP /dev/stream${c} --xuset-br $camera_bps
        H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create src${c} v4l2src device=/dev/stream${c} io-mode=mmap ! "video/x-h264,stream-format=(string)byte-stream,width=(int)1920,height=(int)1080,framerate=(fraction)${FPS}/1" ! h264parse config-interval=$SPS ! omxh264dec disable-dpb=true ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # H.264 stream no SCALING (pull desired resolution and frame rate directly off)
    elif [ -c /dev/stream${c} ] && [[ " ${FLAGS[@]} " =~ "native" ]] ; then
        H264_UVC_TestAP /dev/stream${c} --xuset-br $bps
        H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create src${c} v4l2src device=/dev/stream${c} io-mode=mmap ! "video/x-h264,stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! h264parse config-interval=$SPS ! omxh264dec disable-dpb=true ! videoconvert ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # RAW stream w/SCALING (pull camera at highest available res, then scale to desired resolution)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "xraw" ]] && ${SCALING} ; then
        gst-client pipeline_create src${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "video/x-raw,format=(string)YUY2,width=(int)800,height=(int)600,framerate=(fraction)15/1" ! videorate max-rate=$FPS skip-to-first=true ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # RAW stream w/o SCALING (pull camera at closest resolution, then scale to desired resolution)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "xraw" ]] ; then
        gst-client pipeline_create src${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "video/x-raw,format=(string)YUY2,width=(int)640,height=(int)360,framerate=(fraction)${FPS}/1" ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # MJPG stream w/SCALING (pull camera MJPEG at highest available res, then scale to desired resolution)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "mjpg" ]] && ${SCALING} ; then
        H264_UVC_TestAP /dev/cam${c} --xuset-mjb $camera_mjb
        gst-client pipeline_create src${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "image/jpeg,width=(int)1920,height=(int)1080,framerate=(fraction)${FPS}/1" ! nvjpegdec idct-method=ifast ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # MJPG stream no SCALING (pull camera MJPEG at desired resolution and frame rate)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "mjpg" ]] ; then
        H264_UVC_TestAP /dev/cam${c} --xuset-mjb $camera_mjb
        gst-client pipeline_create src${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "image/jpeg,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! nvjpegdec idct-method=ifast ! videoconvert ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    # Either no camera or invalid FLAGS
    else
        if [ -c /dev/cam${c} ] ; then pattern=spokes ; else pattern=solid-color ; fi
        if [ "${c}" == "1" ] ; then color=$RED ; else color=$BLU ; fi
        gst-client pipeline_create src${c} videotestsrc is-live=true pattern=$pattern foreground-color=$color ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam${c}
    fi
  # Front/Rear Camera Loop
  done
    # Thermal camera is raw only (so use /dev/cam2)
    if [ -c /dev/cam2 ] ; then
        gst-client pipeline_create src2 v4l2src device=/dev/cam2 io-mode=mmap ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${boson_fps}/1" ! videorate max-rate=$FPS skip-to-first=true ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${FPS}/1" ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
    else
        gst-client pipeline_create src2 videotestsrc is-live=true pattern=solid-color foreground-color=$GRN ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! interpipesink name=cam2
    fi
    # one encoder pipeline
    # https://raspberrypi.stackexchange.com/questions/26675/modern-way-to-stream-h-264-from-the-raspberry-cam
    # NB: the encoder, xvideo, parser and payloader variables contain the selected pipeline type
    gst-client pipeline_create stream1 interpipesrc name=switch block=true listen-to=cam1 is-live=true allow-renegotiation=true stream-sync=compensate-ts ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL
    # bug in interpipe requires RX to start first; or use stream-sync=2 (compensate-ts)
    gst-client pipeline_play stream1
    # start pipelines streaming
    gst-client pipeline_play src1
    gst-client pipeline_play src2
    gst-client pipeline_play src3
    # NB: may need a gratuitous switch
    gst-client element_set stream1 switch listen-to cam1
#
# no-interpipe: three independent streams selectively enabled
#
else
  for c in 1 3 ; do
    # Front camera is /dev/cam1, /dev/stream1 producing 'stream1'
    # Rear camera is /dev/cam3, /dev/stream3 producing 'stream3'
    # H.264 stream w/SCALING (pull camera at high res, then transcode to desired resolution)
    if [ -c /dev/stream${c} ] && [[ " ${FLAGS[@]} " =~ "native" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] && ${SCALING} ; then
        H264_UVC_TestAP /dev/stream${c} --xuset-br $camera_bps
        H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create stream${c} v4l2src device=/dev/stream${c} io-mode=mmap ! "video/x-h264,stream-format=(string)byte-stream,width=(int)1920,height=(int)1080,framerate=(fraction)${FPS}/1" ! h264parse config-interval=$SPS ! omxh264dec disable-dpb=true ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    # H.264 stream no SCALING (pull desired resolution and frame rate directly off)
    elif [ -c /dev/stream${c} ] && [[ " ${FLAGS[@]} " =~ "native" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] ; then
        H264_UVC_TestAP /dev/stream${c} --xuset-br $bps
        H264_UVC_TestAP /dev/stream${c} --xuset-gop $GOP
        gst-client pipeline_create stream${c} v4l2src device=/dev/stream${c} io-mode=mmap ! "video/x-h264,stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! h264parse config-interval=$SPS ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    # RAW stream w/SCALING (pull camera at highest available res, then scale to desired resolution)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "xraw" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] && ${SCALING} ; then
        gst-client pipeline_create stream${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "video/x-raw,format=(string)YUY2,width=(int)800,height=(int)600,framerate=(fraction)15/1" ! videorate max-rate=$FPS skip-to-first=true ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    # MJPG stream w/SCALING (pull camera MJPEG at highest available res, then scale to desired resolution)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "mjpg" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] && ${SCALING} ; then
        H264_UVC_TestAP /dev/cam${c} --xuset-mjb $camera_mjb
        gst-client pipeline_create stream${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "image/jpeg,width=(int)1920,height=(int)1080,framerate=(fraction)${FPS}/1" ! nvjpegdec idct-method=ifast ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    # MJPG stream no SCALING (pull camera MJPEG at desired resolution and frame rate)
    elif [ -c /dev/cam${c} ] && [[ " ${FLAGS[@]} " =~ "mjpg" ]] && [[ " ${FLAGS[@]} " =~ "h264" ]] ; then
        H264_UVC_TestAP /dev/cam${c} --xuset-mjb $camera_mjb
        gst-client pipeline_create stream${c} v4l2src device=/dev/cam${c} io-mode=mmap ! "image/jpeg,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! nvjpegdec idct-method=ifast ! videoconvert ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    # Either no camera or invalid FLAGS
    else
        if [ -c /dev/cam${c} ] ; then pattern=spokes ; else pattern=solid-color ; fi
        if [ "${c}" == "1" ] ; then color=$RED ; else color=$BLU ; fi
        gst-client pipeline_create stream${c} videotestsrc is-live=true pattern=$pattern foreground-color=$color ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream${c}.json
    fi
  # Front/Rear Camera Loop
  done
    # Thermal camera is raw only (so use /dev/cam2)
    if [ -c /dev/cam2 ] ; then
        gst-client pipeline_create stream2  v4l2src device=/dev/cam2 io-mode=mmap ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${boson_fps}/1" ! videorate max-rate=$FPS skip-to-first=true ! "video/x-raw,format=(string)${boson_format},width=(int)${boson_width},height=(int)${boson_height},framerate=(fraction)${FPS}/1" ! ${scaler} ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream2.json
    else
        gst-client pipeline_create stream2 videotestsrc is-live=true pattern=solid-color foreground-color=$GRN ! "video/x-raw,format=(string)$FORMAT,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${encoder} ! "video/${xvideo},stream-format=(string)byte-stream,width=(int)$WIDTH,height=(int)$HEIGHT,framerate=(fraction)${FPS}/1" ! ${parser} ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=$qmst min-threshold-buffers=1 leaky=upstream ! ${payloader} ! mux.sink_0 rtpmux name=mux ! udpsink name=output sync=false host=$UDP_HOST port=$UDP_PORT ttl=$UDP_TTL > /tmp/stream2.json
    fi
    # start one pipeline at a time, switching is SLOW; achieved by stopping, starting and pausing pipelines
    gst-client pipeline_play stream1
    gst-client pipeline_pause stream2
    gst-client pipeline_stop stream3
fi
set +x
