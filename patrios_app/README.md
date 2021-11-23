# Patrios Vehicle Application
Code to configure and operate a UGV


## Features

 1. Static IP for RJ45 (ethernet) network - edit /etc/systemd/network.conf.  `172.20.x.y/16`.
 2. Use a proxy to/from UART to Pixhawk and `udp://172.20.255.255:14550`.
 3. Video pipeline from one of three cameras streaming RTP payload 96 to endpoint specified in config file.
    a. use [udev rules](https://wiki.archlinux.org/index.php/Udev#Video_device) to assign cameras to `/dev/cam1`, `/dev/cam2`, etc.
    b. use [gst-client](https://developer.ridgerun.com/wiki/index.php/Digital_Zoom,_Pan_and_Tilt_using_Gstreamer_Daemon) to setup pipelines so that they can be controlled by a separate program
 4. Interpret the [mavlink camera api](https://mavlink.io/en/services/camera.html)
    a. filter on messages from the GCS to the Pixhawk and on the SYSID of the Pixhawk
    b. only the `[MAV_CMD_SET_CAMERA_MODE](https://mavlink.io/en/messages/common.html#MAV_CMD_SET_CAMERA_MODE)` will be interpreted, the component ID of [MAV_COMP_ID_CAMERA](https://mavlink.io/en/messages/common.html#MAV_COMP_ID_CAMERA), MAV_COMP_ID_CAMERA2, etc. will identify which camera to activate.  There will be no acknowledge.
 5. No telemetry or other data will be stored in persistent storage.
 8. FPS can be adjusted to `15` or `30` by video configuration `FPS`

## First Time Setup
When setting up on a new machine image, please perform:
```
make postinstall
```

This will perfom the following steps:
 1. create `h31` user, with password and extra groups
 2. copy files to ~h31/patrios_app
 3. delete autologin (see https://github.com/climr/patrios_app/issues/8)
 4. change hostname to serial number
 5. tell user that a reboot will occur and that they are to login as the `h31` user, and re-run 'make postinstall'
 6. upon the re-run in the `h31`, remove the nvidia user
 7. run the below `Setup` steps in sequence

At this point the machine is setup according to the factory documentation and will perform the intended function.

## First Time Setup
When setting up on a new machine image, please perform:
```
make postinstall
```

This will perfom the following steps:
 1. create `h31` user, with password and extra groups
 2. copy files to ~h31/patrios_app
 3. ensure that /config folder exists, if not then link to /usr/local/h31/conf
 4. delete autologin (see https://github.com/climr/patrios_app/issues/8)
 5. change hostname to serial number
 6. tell user that a reboot will occur and that they are to login as the `h31` user, and re-run 'make postinstall'
 7. upon the re-run in the `h31`, remove the nvidia user
 8. run the below `Setup` steps in sequence

At this point the machine is setup according to the factory documentation and will perform the intended function.

## Setup
To configure the software, execute the following commands:
```
make dependencies
make install
make provision
```

This can be done on a variety supported machines and operating systems that are Debian-based (Debian, Ubuntu, etc.) and which use `systemd` as the init program.  The commands are typically called in the above order (required for first time setup), but afterward can be done in any order desired or a-la-carte.

### `make dependencies`
This ensures that the operating system has the necessary libraries, programs and configurations needed to operate the software.  It uses the system package manager or pulls source code and compiles it as necessary and appropriate.  It is via this command that the operating system is updated for security patches as needed.

### `make install`
This causes the needed services and programs to be added to the system so that they will execute upon power on of the system.  The philosophy of the software is that all code and configurations be part of the system.  The files in this repository only exist to manipulate and configure the system, but otherwise are not a necessary part.  This means, for example, that an external device could hold this code, setup the system and then be removed.

To configure the software, edit the files in `/usr/local/h31/conf/*.conf`.
For convenience of command-line adjustments, login to the CPU and execute the following commands:

### `make -C /usr/local/h31 provision`
This causes all the settings to be inspected and interactively changed *(including the network settings)*.  Typically, this command is executed by the factory to setup the various configurations needed to operate the software.  For users, there are typically two (sub-)configurations that they can use to make adjustments:

#### `make -C /usr/local/h31 provision-cameras`
This offers the opportunity to (re-)assign which physical camera is associated with the EO, Thermal and Rear camera systems.  It is somewhat dependent on the settings made in `provision-video`, below, so typically `provision-video` is called first.  The dependency comes from the selection of data format ('xraw', 'mjpg', or 'encd') because the cameras have different interfaces for those modes.

#### `make -C /usr/local/h31 provision-video`
This offers the opportunity to adjust parameters of the video streaming service that applies to all cameras.  The following items are adjustable:

##### UDP_HOST
This defines the IPv4 address for the video destination.  By convention, this is `224.1.x.y` on port 5600 where 'x', 'y' are the lower two octets of *this* machine's network address.  This is necessary to separate out the video streams such as when a certain vehicle is selected for control, the corresponding video stream is selected.  Using multicast UDP for video allows for conservation of bandwidth such that only those GCS and endpoints that are interested in the video will consume bandwidth on the wireless mesh network.

##### WIDTH, HEIGHT, FPS
These parameters define the size of the encoded video frame and frame rate.  Together with the H264_BITRATE and FLAGS, they can affect the quality of the video as well as the latency.  Higher frame rates lead to lower latency, but cameras are limited to certain frame rates.  **(currently, the software does not alter the frame rate so all cameras must be able to support the frame rate entered here).**

##### VIDEO_BITRATE
This parameter (given in kbits/sec) is passed to the video encoder to maintain a constant bitrate over the network.  Constant bitrate encoding produces **consistent** latency at the expense of variable quality.  Selecting too low a value to a large video frame and rate leads to poor **(blurry)** quality while selecting too high a value can lead to video artifacts due to loss of wireless signal.  Experimentation is needed according to the users' needs.  Typically, `1800` is a good starting point for H.264 720p video at 15 fps, while `1400` is good for H.265 video at the same resolution.


## Services
The following services will be configured to execute upon system startup.

### camera-switcher/gstd
The GStreamer client.  This is a service that provides for dynamic GStreamer pipelines that can be inspected and controlled during runtime using a local socket protocol.  The `camera-switcher` service calls a shell script that was generated by the `make provision` steps.  The service accepts control via the `gst-client` program to start/stop and alter the video pipelines. This service also streams audio from the first h264 camera encountered.

### h31proxy
The program to connect a multicast UDP port to the autopilot.  The program connects UDP packets to/from the autopilot.  It also inspects the commands from the GCS to the autopilot and makes system calls using `gst-client` to change video camera streams.

### temperature
A program to take temperature measurements and store them in **volatile** memory for diagnostic and development.  **(currently, the file must be manually downloaded over the network; subsequent releases may incorporate this into `h31proxy` to send temperature telementry to the GCS).**

## Video System Troubleshooting

If you are not getting a video feed on the GCS, follow these steps to help debug:

1. Ensure there are no issues with the USB wiring, cameras, etc.
```
sudo apt-get install v4l-utils
v4l2-ctl --list-devices
```
You should see at least 2 H.264 sources and one Boson source. If you don't see them all, check to make sure that you have all 3 USB cameras:
```
lsusb
```
You should see 3 devices which correspond to the attached cameras. Verify that you are not getting "usb disconnect" errors in the dmesg output
```
dmesg -w
```
any usb disconnect and reconnect is a sign that the wiring is faulty or the camera is fault. Replace and retry.

2. Check the camera-switcher software
```
sudo systemctl status camera-swticher
```
this should show the service active:running. If not, start it using ```sudo systemctl start camera-switcher``` and investigate why it didn't start automatically.

Try to restart the service and see if the stream starts
```
sudo systemctl restart camera-switcher
```
If a restart causes the stream to start on the GCS, this could indicate that a camera is faulty (normally you would see "usb disconnect" in the dmesg log as well) or it could indicate some kind of unique startup/race condition where the camera-switcher service started before the network was ready for streaming.

3. Check the camera-switcher logs for any clues
Look at the output of
```
sudo journalctl -u camera-swticher | grep "Warning"
```
and
```
sudo journalctl -u camera-swticher | grep "Bad"
```
if either of the commands above return results, investigate the source of those errors.

4. Check udev rules. 
```
ls /dev/stream*
```
should return /dev/stream1 and /dev/stream3
```
ls /dev/cam*
```
should return /dev/cam2  

5. The video system uses a relatively complicated gstreamer dameon, at this point you can try to run a simple script to verify video works. Stop the camera-switcher service and then run a simple gst-launch pipeline using /dev/stream1.   

Change the ip address 172.20.3.29 in the below command to match the actual ip address of the GCS you are streaming to  
Within QGroundControl, change video settings to Unicast h.264, port 5600  
Now run the commands below  
```
sudo systemctl stop camera-switcher
gst-launch-1.0 v4l2src device=/dev/stream1 ! "video/x-h264,width=1280,height=720,framerate=15/1" ! rtph264pay config-interval=1 pt=96 ! udpsink host=172.20.3.29 port=5600 multicast-iface=eth0 auto-multicast=true ttl=10
```
6. Check QGCS Console for clues. Within QGCS, click top left icon > application settings > console. If you see repeating messages that the GCS is requesting the video endpoint, that just means the GCS is not receive the stream and trying again. Other messages may provide additional clues.

7. Network issues - video is multicast and requires the radio system used to support multicast messaging. Although rare, we have seem some cases where a multicast route gets corrupted for an unknown reason on the Windows controllers. You can try to change the host LOS video address to a different IP address using the webUI. Also ensure the network interface on the GCS system is a "Private Network."
![image](https://user-images.githubusercontent.com/13543163/142952215-48a045f5-f8d4-4342-9468-972ab7c4544a.png)


## References
* [mavlink camera api](https://mavlink.io/en/services/camera.html)
* [RidgeRun Wiki](https://developer.ridgerun.com/wiki/index.php/Digital_Zoom,_Pan_and_Tilt_using_Gstreamer_Daemon)
* [udev rules](https://wiki.archlinux.org/index.php/Udev#Video_device)

