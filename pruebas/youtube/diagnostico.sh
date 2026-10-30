#!/bin/sh
# Experimento (no fusionar): costo de agrandar el video a pantalla completa
# sin 3D (vo=x11, escalado por procesador) y efecto de sws-scaler.
set -u
apk update >/dev/null
apk add -q mpv ffmpeg xvfb font-dejavu mesa-dri-gallium procps >/dev/null
Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 &
export DISPLAY=:99 HOME=/tmp/casa; mkdir -p $HOME
sleep 2
ffmpeg -loglevel error -f lavfi -i testsrc=size=854x480:rate=30 -f lavfi -i sine -t 40 -c:v libx264 -c:a aac /tmp/v.mp4
ticks() { awk '{print $14+$15}' /proc/$1/stat 2>/dev/null; }
medir() {
	mpv --ao=null --vo=x11 --length=25 --really-quiet "$@" /tmp/v.mp4 >/tmp/o 2>&1 &
	pid=$!; sleep 8; t1=$(ticks $pid); sleep 10; t2=$(ticks $pid)
	wait $pid 2>/dev/null
	echo "MEDIDA $*: cpu=$(( (t2 - t1) * 100 / 1000 ))% de un nucleo"
	grep -iE 'error|option' /tmp/o | head -3
}
medir
medir --fs
medir --fs --sws-scaler=fast-bilinear
medir --fs --sws-scaler=fast-bilinear --sws-fast=yes
medir --fs --sws-scaler=point
