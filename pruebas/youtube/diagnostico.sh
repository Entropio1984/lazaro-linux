#!/bin/sh
# Experimento (no fusionar): mpv se cae en una VM sin 3D
# ("Assertion failed: !vo->x11"). Probar salidas de video.
set -u
apk update >/dev/null
apk add -q mpv ffmpeg xvfb font-dejavu mesa-dri-gallium mesa-vulkan-swrast \
	mesa-vulkan-intel mesa-vulkan-ati mesa-gbm mesa-egl vulkan-loader curl >/dev/null
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
curl -fsSL https://raw.githubusercontent.com/Entropio1984/alpine-desktop-setup/youtube-ligero/desktop-postinstall.sh -o /tmp/s.sh
mkdir -p /etc/mpv
sed -n "/cat > \/etc\/mpv\/mpv.conf <<'MPV'/,/^MPV\$/p" /tmp/s.sh | sed '1d;$d' > /etc/mpv/mpv.conf
grep -E '^(vo|gpu-context)=' /etc/mpv/mpv.conf
echo "==== con la configuración nueva, sin 3D (Xvfb)"
timeout 10 mpv --ao=null --length=3 -v /tmp/v.mp4 >/tmp/o 2>&1; echo "codigo=$?"
grep -E 'VO:|Assertion|Abort|Exiting' /tmp/o
echo "==== mismo, sesión Wayland inexistente forzada (WAYLAND_DISPLAY falso)"
WAYLAND_DISPLAY=nada timeout 10 mpv --ao=null --length=3 -v /tmp/v.mp4 >/tmp/o 2>&1; echo "codigo=$?"
grep -E 'VO:|Assertion|Abort|Exiting' /tmp/o
