#!/bin/sh
# Ver .github/workflows/prueba-youtube.yml
set -u
R=/tmp/res; mkdir -p $R
apk update >/dev/null
echo "== Núcleos: $(nproc)  Memoria: $(awk '/MemTotal/{print $2/1024 " MB"}' /proc/meminfo)  cgroup: $(cat /sys/fs/cgroup/cpu.max 2>/dev/null) $(cat /sys/fs/cgroup/memory.max 2>/dev/null)"

# --- Tamaño --------------------------------------------------------------
apk add -q xorg-server xfce4 lightdm firefox vlc vlc-qt libreoffice flatpak \
	font-dejavu font-noto mate-desktop-environment lxqt-desktop >/dev/null 2>&1
medir() {
	nombre="$1"; shift
	nuevos=$(apk add --simulate "$@" 2>/dev/null | sed -n 's/^([ 0-9]*\/[0-9]*) Installing \([^ ]*\) (\(.*\))$/\1/p')
	rm -rf /tmp/m && mkdir -p /tmp/m
	[ -z "$nuevos" ] || apk fetch -q -o /tmp/m $nuevos >/dev/null 2>&1
	echo "TAMANO $nombre: $(printf '%s\n' "$nuevos" | grep -c .) paquetes nuevos, $(du -sm /tmp/m | cut -f1) MB"
	echo "  $(echo $nuevos)"
}
medir youtube pipe-viewer pipe-viewer-gtk mpv yt-dlp
medir deno deno

# --- Instalar -------------------------------------------------------------
apk add -q pipe-viewer pipe-viewer-gtk mpv yt-dlp deno xvfb xdotool coreutils procps \
	font-dejavu adwaita-icon-theme mesa-dri-gallium >/dev/null
apk info -e yt-dlp yt-dlp-ejs yt-dlp-ejs-rt-quickjs yt-dlp-ejs-rt-nodejs quickjs quickjs-ng nodejs deno
for p in pipe-viewer pipe-viewer-gtk mpv yt-dlp yt-dlp-ejs quickjs deno; do echo "VERSION $(apk info -d $p 2>/dev/null | head -1)"; done
command -v qjs; ls /usr/lib/python3*/site-packages | grep -i ejs

Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 2

# --- Configuración por defecto de pipe-viewer -----------------------------
export HOME=/tmp/casa; mkdir -p $HOME
timeout 20 gtk-pipe-viewer >/dev/null 2>&1
timeout 20 pipe-viewer --version >/dev/null 2>&1
echo n | timeout 20 pipe-viewer -n --results=1 --novideo prueba >/dev/null 2>&1
ls -la $HOME/.config/pipe-viewer/
cp $HOME/.config/pipe-viewer/*.conf $R/ 2>/dev/null
grep -nE "video_player_selected|resolution|prefer_mp4|ignore_av1|prefer_av1|hfr|split_videos|dash|ytdl|show_thumbs|maxResults" $HOME/.config/pipe-viewer/*.conf

# --- Configuración propuesta ----------------------------------------------
cp pruebas/youtube/yt-dlp.conf /etc/yt-dlp.conf
mkdir -p /etc/mpv && cp pruebas/youtube/mpv.conf /etc/mpv/mpv.conf
mkdir -p $HOME/.config/mpv/scripts && cp pruebas/youtube/medir.lua $HOME/.config/mpv/scripts/

# Muestreo de CPU y RAM de mpv cada 5 s mientras corra.
vigilar() {
	while :; do
		p=$(pgrep -x mpv | head -1)
		if [ -n "$p" ]; then
			top -b -n 1 -p "$p" 2>/dev/null | awk -v p="$p" '$1==p {print "TOP mpv cpu=" $9 "% mem=" $10 "% res=" $6}'
		fi
		sleep 5
	done
}
sello() { while IFS= read -r l; do echo "$(date +%s.%N | cut -c1-14) $l"; done; }

probar() { # NOMBRE BUSQUEDA [OPCIONES pipe-viewer]
	nombre="$1"; busqueda="$2"; shift 2
	echo "== $nombre: '$busqueda'"
	vigilar & v=$!
	ini=$(date +%s.%N | cut -c1-14)
	echo "$ini INICIO"
	timeout 180 pipe-viewer -n --results=1 --player=mpv --resolution=480 --prefer-mp4 --ignore-av1 --no-hfr \
		--append-arg="--ao=null --vo=x11" "$@" "$busqueda" 2>&1 | sello | tee $R/$nombre.log \
		| grep -E "INICIO|MEDIR|Error|error|\[!\]|Resolution|itag" | head -20
	kill $v 2>/dev/null
	f=$(grep -m1 MEDIR-INICIO $R/$nombre.log | cut -d' ' -f1)
	[ -n "$f" ] && echo "RESULTADO $nombre: $(echo "$f - $ini" | bc 2>/dev/null || awk "BEGIN{print $f-$ini}") s desde Enter hasta el video" \
		|| echo "RESULTADO $nombre: NO ARRANCÓ"
}
apk add -q bc >/dev/null 2>&1

for motor in quickjs deno; do
	sed -i "s/^--js-runtimes .*/--js-runtimes $motor/" /etc/yt-dlp.conf
	echo "######## Motor JS: $motor"
	probar "$motor-largo" "documental completo historia" --duration=long
	probar "$motor-musical" "musica andina video oficial"
	probar "$motor-envivo" "lofi hip hop radio" --features=live
	echo "== yt-dlp directo ($motor)"
	/usr/bin/time -f "TIEMPO yt-dlp $motor %e s, %M KB máx" yt-dlp -g \
		-f 'bestvideo[height<=?480][vcodec^=avc1][fps<=30]+bestaudio/best[height<=?480]' \
		"ytsearch1:documental historia" 2>&1 | tail -3
done
echo "== yt-dlp -v (por si falló algo)"
yt-dlp -v -F "ytsearch1:musica andina video oficial" > $R/yt-dlp-v.log 2>&1
grep -iE "js|runtime|challenge|error|warning|sign in|bot" $R/yt-dlp-v.log | head -30
exit 0
