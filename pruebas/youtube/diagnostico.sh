#!/bin/sh
# Experimento (no fusionar): por qué mpv no abre en el sistema instalado.
set -u
apk update >/dev/null
apk add -q pipe-viewer pipe-viewer-gtk mpv yt-dlp yt-dlp-ejs-rt-quickjs ffmpeg xvfb \
	font-dejavu adwaita-icon-theme mesa-dri-gallium curl >/dev/null
curl -fsSL https://raw.githubusercontent.com/Entropio1984/alpine-desktop-setup/youtube-ligero/desktop-postinstall.sh -o /tmp/s.sh
mkdir -p /etc/mpv
sed -n "/cat > \/etc\/mpv\/mpv.conf <<'MPV'/,/^MPV\$/p" /tmp/s.sh | sed '1d;$d' > /etc/mpv/mpv.conf
sed -n "/cat > \/etc\/yt-dlp.conf <<'YTDLP'/,/^YTDLP\$/p" /tmp/s.sh | sed '1d;$d' > /etc/yt-dlp.conf
echo "==== /etc/mpv/mpv.conf"; cat /etc/mpv/mpv.conf
echo "==== mpv --version"; mpv --version
echo "==== mpv.desktop"; grep -E '^(Exec|TryExec)' /usr/share/applications/mpv.desktop
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
export DISPLAY=:99 HOME=/tmp/casa; mkdir -p $HOME
sleep 2
ffmpeg -loglevel error -f lavfi -i testsrc=size=854x480:rate=30 -f lavfi -i sine -t 20 -c:v libx264 -c:a aac /tmp/v.mp4
echo "==== 1. con la configuración, archivo local, salida por defecto"
timeout 8 mpv --length=4 /tmp/v.mp4 2>&1 | tail -n 25; echo "codigo=$?"
echo "==== 2. sin configuración"
timeout 8 mpv --no-config --length=4 /tmp/v.mp4 2>&1 | tail -n 15
echo "==== 3. como el lanzador del menú (sin archivo)"
timeout 6 mpv --player-operation-mode=pseudo-gui -- 2>&1 | tail -n 25; echo "codigo=$?"
echo "==== 4. revisar opciones de la configuración"
for o in ytdl-format hwdec cache demuxer-max-bytes demuxer-max-back-bytes; do
	mpv --list-options 2>/dev/null | grep -q -- "--$o " && echo "existe $o" || echo "NO EXISTE $o"
done
echo "==== 5. YouTube (en CI suele pedir 'no soy un robot')"
timeout 40 mpv -v --length=3 "https://www.youtube.com/watch?v=jNQXAC9IVRw" 2>&1 | grep -iE 'ytdl|error|fail|format|vo/|Playing' | head -n 40
