#!/bin/sh
# TEMPORAL (se borra antes de fusionar): saca capturas de Sway con Claudito
# Shell Fusion tal como lo arma Lázaro (paquetes quickshell y
# lazaro-claudito), para el README y el manual. Corre en un contenedor
# alpine:3.24 como root, con el repositorio en /src y las imágenes en /out.
set -eu
msg() { printf '\n==== %s\n' "$*"; }
printf '%s\n%s\n' https://dl-cdn.alpinelinux.org/alpine/v3.24/main \
	https://dl-cdn.alpinelinux.org/alpine/v3.24/community > /etc/apk/repositories
apk update -q
apk add -q alpine-sdk openssl tar

msg "Empaquetando quickshell y lazaro-claudito"
adduser -D -G abuild constructor
H=/home/constructor
mkdir -p "$H/.abuild" "$H/repo"
openssl genrsa -out "$H/.abuild/c.rsa" 2048 2>/dev/null
openssl rsa -in "$H/.abuild/c.rsa" -pubout -out "$H/.abuild/c.rsa.pub" 2>/dev/null
echo "PACKAGER_PRIVKEY=\"$H/.abuild/c.rsa\"" > "$H/.abuild/abuild.conf"
cp "$H/.abuild/c.rsa.pub" /etc/apk/keys/
cp -r /src/paquetes/quickshell /src/paquetes/lazaro-claudito "$H/"
chown -R constructor:abuild "$H"
for pq in quickshell lazaro-claudito; do
	cd "$H/$pq"
	for espera in 30 90 180 0; do
		su constructor -c "abuild fetch" > /tmp/fetch.log 2>&1 && break
		[ "$espera" = 0 ] || sleep "$espera"
	done
	su constructor -c "REPODEST=$H/repo abuild -r" > "/tmp/abuild-$pq.log" 2>&1 ||
		{ tail -n 80 "/tmp/abuild-$pq.log"; exit 1; }
done
echo "$H/repo/constructor" >> /etc/apk/repositories
apk update -q

msg "Sway sin pantalla con Claudito"
apk add -q lazaro-claudito sway foot fastfetch dbus grim font-dejavu font-noto \
	adwaita-icon-theme mesa-dri-gallium musl-locales mousepad
cp /usr/bin/sway /usr/local/bin/sway
install -Dm644 /src/live/usr/share/backgrounds/lazaro/lazaro-fondo.jpg \
	/usr/share/backgrounds/lazaro/lazaro-fondo.jpg
echo 'output HEADLESS-1 resolution 1366x768' > /etc/sway/config.d/00-captura.conf
adduser -D -s /bin/sh julian
U=/home/julian
mkdir -p "$U/run" "$U/.config/fastfetch"
chmod 700 "$U/run"
chown -R julian "$U"
su julian -c "cd; export XDG_RUNTIME_DIR=$U/run WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 QT_QUICK_BACKEND=software LANG=es_ES.UTF-8 LC_ALL=es_ES.UTF-8; exec dbus-run-session /usr/local/bin/sway" > /tmp/sway.log 2>&1 &
sleep 30
sock=$(ls "$U/run"/wayland-* 2>/dev/null | grep -v lock | head -n 1)
ipc=$(ls "$U/run"/sway-ipc.* 2>/dev/null | head -n 1)
como() { su julian -c "export XDG_RUNTIME_DIR=$U/run WAYLAND_DISPLAY=${sock##*/} SWAYSOCK=$ipc LANG=es_ES.UTF-8; $*"; }
foto() { sleep "${2:-6}"; como grim "/tmp/$1.png" && cp "/tmp/$1.png" "/out/$1.png" && echo "captura $1 OK"; }
pgrep -u julian -x qs >/dev/null && echo "Claudito (qs) corriendo" || { echo "qs NO corre"; cat "$U/run/lazaro-claudito.log" 2>/dev/null; }
como "swaymsg exec 'foot -e sh -c \"fastfetch; exec sh\"'"
como "swaymsg exec mousepad"
foto sway-claudito 10
como "qs -c sway-bar ipc call launcher toggle"
foto sway-claudito-menu
como "qs -c sway-bar ipc call launcher toggle" || true
como "qs -c sway-bar ipc call keybinds toggle"
foto sway-claudito-atajos
como "qs -c sway-bar ipc call keybinds toggle" || true
echo "--- registro de Sway:"; head -n 60 /tmp/sway.log
echo "--- registro de Claudito:"; head -n 60 "$U/run/lazaro-claudito.log" 2>/dev/null || true
