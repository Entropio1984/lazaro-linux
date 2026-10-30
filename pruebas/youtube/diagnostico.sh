#!/bin/sh
# Experimento (no fusionar): mpv se cae en una VM sin 3D
# ("Assertion failed: !vo->x11"). Probar salidas de video.
set -u
apk update >/dev/null
apk add -q mpv ffmpeg xvfb font-dejavu mesa-dri-gallium mesa-vulkan-swrast \
	mesa-vulkan-intel mesa-vulkan-ati mesa-gbm mesa-egl vulkan-loader >/dev/null
apk add -q mesa-vulkan-layers >/dev/null 2>&1
apk info -e mesa-dri-gallium mesa-vulkan-swrast mesa-vulkan-intel mesa-vulkan-ati
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
export DISPLAY=:99 HOME=/tmp/casa; mkdir -p $HOME
sleep 2
ffmpeg -loglevel error -f lavfi -i testsrc=size=854x480:rate=30 -f lavfi -i sine -t 20 -c:v libx264 -c:a aac /tmp/v.mp4
p() {
	echo "==== mpv $*"
	timeout 10 mpv --ao=null --length=3 -v "$@" /tmp/v.mp4 >/tmp/o 2>&1
	echo "codigo=$?"
	grep -iE 'Suspected|Assertion|Abort|Initializing GPU context|context|Selected|VO:|Error|fail' /tmp/o | grep -v 'Assuming' | head -n 25
}
p
p --vo=gpu-next --gpu-api=opengl
p --vo=gpu-next --gpu-context=x11egl
p --vo=gpu-next --gpu-context=wayland,x11egl
p --vo=gpu-next,x11 --gpu-context=wayland,x11egl
p --vo=gpu --gpu-context=x11egl
echo "==== mpv --vo=help"; mpv --vo=help | head -30
echo "==== mpv --gpu-context=help"; mpv --gpu-context=help
