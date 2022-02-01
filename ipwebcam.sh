#!/bin/bash

export ANDROID_SERIAL=`adb devices -l | grep -i oneplus | awk '{print $1}'`
export HOST_PORT=8080
export IPWEBCAM_PORT=8080
export V4L2_DEVICE=/dev/video0


function start_screen_mirror(){
    if [ ! `pgrep scrcpy` ];then
        echo 'starting screen mirroring'
        scrcpy -s $ANDROID_SERIAL
    else
        echo 'screen mirroring is already running'
    fi
}


function stop_screen_mirror(){
    if [ `pgrep scrcpy` ];then
        echo 'stopping screen mirroring'
        kill -9 `pgrep scrcpy`
    else
        echo 'screen mirroring is not running'
    fi
}


function start_ipwebcam(){
    # forward port from android to host system
    adb forward "tcp:$HOST_PORT" "tcp:$IPWEBCAM_PORT"
            
    # check if ipwebcam is rolling i.e., server running
    IS_IW_ROLLING=$(adb shell "dumpsys activity activities" | grep com.pas.webcam.pro | grep ActivityRecord | grep mLastOrientationSource | grep Rolling)
    if [[ ! $IS_IW_ROLLING ]]; then
        echo "starting ipwebcam server"

        # open ipwebcam config page if not already
        IS_IW_CONFIG_PAGE=`adb shell "dumpsys activity activities" | grep mResumedActivity | grep Configuration`
        if [[ ! $IS_IW_CONFIG_PAGE ]]; then
            # start ipwebcam application
            adb shell monkey -p com.pas.webcam.pro 1 >> /dev/null
        fi

        # go to start-server button by swiping (dx, dy)
        adb shell input roll 10 100

        # and press enter
        adb shell input keyevent 66

    else
        echo "ipwebcam server is already running"
    fi
}


function stop_ipwebcam(){
    # remove port forward
    IS_PORT_FORWARD_ACTIVE=$(adb forward --list | grep "tcp:$HOST_PORT")
    if [[ $IS_PORT_FORWARD_ACTIVE ]];then
        adb forward --remove "tcp:$HOST_PORT"
    fi

    # stop ipwebcam application
    IS_IW_RUNNING=$(adb shell ps | grep com.pas.webcam.pro)
    if [[ $IS_IW_RUNNING ]]; then
        echo "stopping ipwebcam server"
        adb shell am force-stop com.pas.webcam.pro
    else
        echo "ipwebcam server is not running"
    fi
}


function start_v4l2loopback(){
    while :
    do
        if [ ! `pgrep -f 'ffmpeg.*v4l2'` ];then
            echo 'starting ffmpeg-v4l2loopback'
            DEFAULT_VIDEO_URL=http://localhost:$HOST_PORT/videofeed

            # make sure v4l2loopback device is available and start publishing videfeed
            modprobe v4l2loopback
            ffmpeg -i ${2:-$DEFAULT_VIDEO_URL} -vf format=yuv420p -f v4l2 $V4L2_DEVICE
        else
            echo 'ffmpeg-v4l2loopback already running'
        fi
        sleep 1
    done
}


function kill_v4l2loopback(){
    PID=`pgrep -f 'ipwebcam.*-f'`
    if [[ $PID ]];then
        kill -9 $PID
        kill -9 `pgrep -f 'ffmpeg.*v4l2'`
        echo 'ffmpeg-v4l2loopback killed'
    else
        echo "ffmpeg-v4l2loopback is not running"
    fi
}

########### Parse Args ###########

# start ipwebcam server on android
if [[ $1 == '-i' ]];then
    start_ipwebcam
    exit
fi


# stop ipwebcam server on android
if [[ $1 == '-q' ]];then
    stop_ipwebcam
    exit
fi


# start screen mirror service
if [[ $1 == '-s' ]];then
    start_screen_mirror
    exit
fi

# stop screen mirror service
if [[ $1 == '-e' ]];then
    stop_screen_mirror
    exit
fi

# get root permission
if  [ "$EUID" -ne 0 ];then
    # call script with sudo
    sudo -E $0 $@;
    exit 0
fi


# start ipwebcam and port forward
if [[ $1 == '-f' ]];then
    start_ipwebcam
    start_v4l2loopback
    exit
fi


# kill v4l2loopback and ffmpeg pipeline
if [[ $1 == '-k' ]];then
    kill_v4l2loopback
    exit
fi


# print help message
echo "usage: $0 [-i|-q|-s|-e|-f|-k]"
echo "-i    start ipwebcam sever"
echo "-q    stop ipwebcam sever"
echo "-s    start screen mirroring"
echo "-e    stop screen mirroring"
echo "-f    start ffmpeg-v4l2loopback"
echo "-k    kill ffmpeg-v4l2loopback"