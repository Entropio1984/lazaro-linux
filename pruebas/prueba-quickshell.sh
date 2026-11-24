#!/bin/sh
# PRUEBA (rama prueba-quickshell, no se fusiona). Corre dentro de un
# contenedor alpine:3.24 como root, con el repositorio en /src.
#  1) Compila Quickshell (paquetes/quickshell) con abuild.
#  2) Mide cuánto pesa (descarga y disco) y qué paquetes nuevos sumaría a
#     una Completa que ya trae los 7 escritorios.
#  3) Arranca Sway sin pantalla con la barra sway-bar de Claudito Shell
#     Fusion, mide su memoria frente a waybar y saca una captura.
set -eu
msg() { printf '\n==== %s\n' "$*"; }
RAMA=v3.24
printf '%s\n%s\n' "https://dl-cdn.alpinelinux.org/alpine/$RAMA/main" \
	"https://dl-cdn.alpinelinux.org/alpine/$RAMA/community" > /etc/apk/repositories
apk update -q
apk add -q alpine-sdk openssl tar

msg "1) Compilando Quickshell"
adduser -D -G abuild constructor
H=/home/constructor
mkdir -p "$H/.abuild" "$H/repo"
openssl genrsa -out "$H/.abuild/prueba.rsa" 2048 2>/dev/null
openssl rsa -in "$H/.abuild/prueba.rsa" -pubout -out "$H/.abuild/prueba.rsa.pub" 2>/dev/null
echo "PACKAGER_PRIVKEY=\"$H/.abuild/prueba.rsa\"" > "$H/.abuild/abuild.conf"
cp "$H/.abuild/prueba.rsa.pub" /etc/apk/keys/
cp -r /src/paquetes/quickshell "$H/quickshell"
chown -R constructor:abuild "$H"
cd "$H/quickshell"
inicio=$(date +%s)
rc=0
su constructor -c "REPODEST=$H/repo abuild -r" > /tmp/abuild.log 2>&1 || rc=$?
echo "Tiempo de compilación: $(( $(date +%s) - inicio )) s"
if [ "$rc" -ne 0 ]; then
	echo "LA COMPILACIÓN FALLÓ ($rc). Últimas líneas:"; tail -n 150 /tmp/abuild.log; exit 1
fi
grep -iE 'warning: |error' /tmp/abuild.log | sort | uniq -c | sort -rn | head -20 || true
APK=$(find "$H/repo" -name 'quickshell-0*.apk' | head -n 1)
echo "Paquete: $APK"
echo "Tamaño del paquete (lo que ocupa en la ISO): $(du -k "$APK" | cut -f1) KB"
echo "$H/repo/constructor" >> /etc/apk/repositories
apk update -q

msg "2) Peso y paquetes nuevos"
# Lista de paquetes con su tamaño (S: descarga, I: instalado) de los índices.
for f in /var/cache/apk/APKINDEX.*.tar.gz "$H/repo/constructor/x86_64/APKINDEX.tar.gz"; do
	tar -xzOf "$f" APKINDEX
done | awk -F: '/^P:/{p=substr($0,3)} /^S:/{s=substr($0,3)} /^I:/{i=substr($0,3)} /^$/{if(p!="")print p, s, i; p=""}' |
	sort -u -k1,1 > /tmp/tamanos.txt
existe() { for p; do grep -q "^$p " /tmp/tamanos.txt && echo "$p"; done; }
# Aproximación de la Completa: los 7 escritorios + lo que pone el script.
BASE=$(existe plasma-desktop plasma-workspace sway waybar fuzzel xfce4 lxqt-desktop mate-desktop-environment \
	gnome gnome-desktop budgie-desktop networkmanager networkmanager-cli bluez upower libnotify \
	pipewire wireplumber pipewire-pulse polkit calamares qt6-qtsvg qt6-qtdeclarative qt6-qtwayland swaylock \
	font-awesome brightnessctl playerctl wl-clipboard)
echo "Base usada: $BASE"
lista() { apk add --simulate --no-cache "$@" 2>/dev/null | sed -nE 's/^\([0-9]+\/[0-9]+\) Installing ([^ ]+) \(.*/\1/p' | sort -u; }
# shellcheck disable=SC2086
lista $BASE > /tmp/a.txt
EXTRA="quickshell font-jetbrains-mono-nerd adw-gtk3 swaylock brightnessctl playerctl libnotify upower bluez networkmanager-cli wl-clipboard qt6-qtsvg"
# shellcheck disable=SC2086
lista $BASE $EXTRA > /tmp/b.txt
echo "Paquetes que sumaría Claudito Shell a la Completa (nombre, descarga, instalado):"
comm -13 /tmp/a.txt /tmp/b.txt | while read -r p; do grep "^$p " /tmp/tamanos.txt || echo "$p ? ?"; done |
	awk '{s+=$2; i+=$3; printf "  %-40s %8.1f MB %8.1f MB\n", $1, $2/1048576, $3/1048576} END {printf "  TOTAL%36s %8.1f MB %8.1f MB\n", "", s/1048576, i/1048576}'
echo "Solo quickshell (sin la Completa), con todo lo que arrastra:"
lista quickshell | while read -r p; do grep "^$p " /tmp/tamanos.txt; done |
	awk '{s+=$2; i+=$3} END {printf "  %d paquetes, descarga %.1f MB, instalado %.1f MB\n", NR, s/1048576, i/1048576}'
grep '^quickshell ' /tmp/tamanos.txt | awk '{printf "quickshell solo: descarga %.1f MB, instalado %.1f MB\n", $2/1048576, $3/1048576}'

msg "3) Sway sin pantalla con Claudito Shell"
apk add -q quickshell sway waybar font-jetbrains-mono-nerd font-dejavu adwaita-icon-theme dbus grim git \
	upower bluez networkmanager-cli pipewire wireplumber libnotify mesa-dri-gallium procps-ng
apk info -e qs >/dev/null 2>&1 || true
command -v qs || ls /usr/bin | grep -i quick
qs --version || quickshell --version || true
adduser -D prueba
# El sway de Alpine trae "capacidades" de archivo que Docker no deja usar
# ("Operation not permitted"): una copia simple las pierde.
cp /usr/bin/sway /usr/local/bin/sway
U=/home/prueba
git clone -q --depth 1 --filter=blob:none --sparse https://gitlab.com/linux-en-casa/claudito-shell-fusion.git /tmp/cs
( cd /tmp/cs && git sparse-checkout set .config/quickshell && git log -1 --format='Claudito Shell Fusion: %h %ad %s' --date=short )
mkdir -p "$U/.config/quickshell" "$U/.config/sway" "$U/run"
cp -r /tmp/cs/.config/quickshell/sway-bar "$U/.config/quickshell/"
cp /tmp/cs/.config/quickshell/*.tsv /tmp/cs/.config/quickshell/*.txt "$U/.config/quickshell/" 2>/dev/null || true
chmod 700 "$U/run"
chown -R prueba "$U"
probar() { # $1 = nombre, $2 = comando de la barra
	cat > "$U/.config/sway/config" <<EOC
output HEADLESS-1 resolution 1366x768
exec $2
EOC
	chown prueba "$U/.config/sway/config"
	rm -f /tmp/barra.log
	su prueba -c "cd; export XDG_RUNTIME_DIR=$U/run WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 QT_QUICK_BACKEND=software LANG=es_ES.UTF-8; exec dbus-run-session /usr/local/bin/sway" > /tmp/barra.log 2>&1 &
	sleep 25
	pid=$(pgrep -u prueba -x "$3" | head -n 1 || true)
	if [ -n "$pid" ]; then
		awk -v n="$1" '/^Rss:/{r=$2} /^Pss:/{p=$2} END {printf "MEMORIA %s: RSS %.0f MB, PSS %.0f MB\n", n, r/1024, p/1024}' "/proc/$pid/smaps_rollup"
		echo "CPU $1 (segundos de procesador en 25 s): $(awk '{printf "%.1f", ($14+$15)/100}' "/proc/$pid/stat")"
	else
		echo "$1: el proceso $3 no está corriendo"
	fi
	if [ "$1" = claudito ]; then
		sock=$(ls "$U/run"/wayland-* 2>/dev/null | grep -v lock | head -n 1)
		su prueba -c "XDG_RUNTIME_DIR=$U/run WAYLAND_DISPLAY=${sock##*/} grim /tmp/captura.png" && {
			echo "CAPTURA-INICIO"; gzip -c /tmp/captura.png | base64 -w 0; echo; echo "CAPTURA-FIN"; } || echo "sin captura"
	fi
	echo "--- registro de $1 (primeras 60 líneas):"; head -n 60 /tmp/barra.log
	pkill -u prueba sway || true; sleep 3; pkill -9 -u prueba || true; sleep 1
}
probar waybar waybar waybar
probar claudito "qs -c sway-bar" qs
