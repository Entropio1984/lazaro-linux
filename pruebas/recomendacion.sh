#!/bin/sh
# Prueba las recomendaciones de live/usr/sbin/lazaro-recomendar sin
# hardware: arma un /sys, un /proc/meminfo y un /proc/mounts falsos para
# cada caso y revisa lo que queda en las configuraciones de Calamares.
#
#   pruebas/recomendacion.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-recomendar"
CONF="$DIR/live/etc/calamares/modules"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fallos=0
fallo() {
	echo "FALLO $nombre: $*"
	fallos=$((fallos + 1))
}

# caso NOMBRE MEMORIA_MB CONTROLADOR DECISION_NVIDIA DISCO_GB
#   CONTROLADOR: el de la pantalla (i915, qxl...)
#   DECISION_NVIDIA: lo que dejó lazaro-graficas (sin-nvidia, activa, seguro)
#   DISCO_GB: disco interno; además hay un USB montado de 16 GB.
caso() {
	nombre="$1"; mb="$2"; drv="$3"; nv="$4"; gb="$5"
	d="$TMP/$nombre"
	mkdir -p "$d/sys/class/drm" "$d/sys/bus/pci/drivers/$drv" "$d/sys/devices/pci0/0000:00:02.0" \
		"$d/sys/block/sda" "$d/sys/block/sdb" "$d/sys/block/loop0" "$d/calamares"
	ln -s "$d/sys/bus/pci/drivers/$drv" "$d/sys/devices/pci0/0000:00:02.0/driver"
	mkdir -p "$d/sys/class/drm/card0"
	ln -s "$d/sys/devices/pci0/0000:00:02.0" "$d/sys/class/drm/card0/device"
	echo $((gb * 1000000000 / 512)) > "$d/sys/block/sda/size"
	echo 0 > "$d/sys/block/sda/removable"
	echo $((16 * 1000000000 / 512)) > "$d/sys/block/sdb/size"
	echo 1 > "$d/sys/block/sdb/removable"
	echo 2000000 > "$d/sys/block/loop0/size"
	printf 'MemTotal:       %d kB\nMemFree:  1000 kB\n' $((mb * 1024)) > "$d/meminfo"
	echo "/dev/sdb1 /media/sdb vfat ro 0 0" > "$d/mounts"
	printf 'DECISION=%s\nMOTIVO=generacion\n' "$nv" > "$d/graficas"
	cp "$CONF/packagechooser-escritorio.conf" "$CONF/netinstall.conf" "$d/calamares/"
	# Dos veces: la segunda no debe acumular cambios.
	for _vez in 1 2; do
		LAZARO_SYS="$d/sys" LAZARO_MEMINFO="$d/meminfo" LAZARO_MOUNTS="$d/mounts" \
			LAZARO_GRAFICAS="$d/graficas" LAZARO_CALAMARES="$d/calamares" \
			LAZARO_RECOMENDACION="$d/run/recomendacion" sh "$PROG" > "$d/salida"
	done
	ESC="$d/calamares/packagechooser-escritorio.conf"
	NET="$d/calamares/netinstall.conf"
}

# espera ESCRITORIO 3D(si/no) FLATPAK(true/false)
espera() {
	grep -qx "default: $1" "$ESC" || fallo "por defecto $(grep '^default:' "$ESC"), se esperaba $1"
	n=$(grep -c '(recomendado para tu equipo)"$' "$ESC")
	[ "$n" = 1 ] || fallo "$n opciones dicen 'recomendado para tu equipo'"
	awk -v id="$1" '/^    - id:/ { e = ($3 == id) } e && /name\[es\]:.*recomendado para tu equipo/ { f = 1 } END { exit !f }' "$ESC" \
		|| fallo "la opción $1 no dice 'recomendado para tu equipo'"
	# Opciones que llevan el aviso de "No recomendado", en orden.
	avisados=$(awk '/^    - id:/ { id = $3 } /description\[es\]:.*No recomendado para este equipo/ { printf "%s ", id }' "$ESC")
	if [ "$2" = no ]; then
		[ "$avisados" = "xfce-wayland gnome plasma sway " ] \
			|| fallo "sin 3D se esperaba el aviso en xfce-wayland gnome plasma sway y está en: $avisados"
	fi
	sel=$(awk '/- name: "Flatpak/ { f = 1; next } f && /selected:/ { print $2; exit }' "$NET")
	[ "$sel" = "$3" ] || fallo "Flatpak marcado=$sel, se esperaba $3"
	n=$(grep -c 'Recomendado para tu equipo' "$ESC")
	[ "$n" = 1 ] || fallo "la frase de recomendación aparece $n veces"
	grep -q 'disco=' "$d/salida" || fallo "no hay resumen: $(cat "$d/salida")"
	echo "$( [ "$fallos" = "${antes:-0}" ] && echo 'OK   ' || echo '     ') $nombre: $(cat "$d/salida")"
	antes=$fallos
}

antes=0
caso portatil-viejo-1gb 1000 i915 sin-nvidia 120
espera lxqt si true
[ "$avisados" = "xfce-wayland gnome plasma sway " ] \
	|| fallo "con 1 GB se esperaba el aviso en xfce-wayland gnome plasma sway y está en: $avisados"

caso portatil-2gb 1750 i915 sin-nvidia 160
espera xfce si true
[ "$avisados" = "xfce-wayland gnome plasma sway " ] \
	|| fallo "con 2 GB se esperaba el aviso en xfce-wayland gnome plasma sway y está en: $avisados"

caso k53sv-4gb 3800 i915 activa 500
espera xfce si true
grep -q 'equipo: 4 GB de RAM' "$ESC" || fallo "la memoria no aparece en el texto"

caso maquina-virtual 4000 qxl sin-nvidia 20
espera xfce no false
grep -q 'Tu disco es pequeño (20 GB)' "$NET" || fallo "falta el aviso de disco pequeño"

caso fermi-sola 8000 nouveau seguro 250
espera xfce no true

caso ryzen-rtx 32000 nouveau activa 1000
espera xfce si true
grep -q 'también puede con cualquiera' "$ESC" || fallo "con 32 GB y 3D debería decir que puede con cualquiera"
if grep -q 'No recomendado para este equipo' "$ESC"; then fallo "con 32 GB y 3D no se desaconseja nada"; fi

caso disco-32gb 2048 amdgpu sin-nvidia 32
espera xfce si false

if [ "$fallos" -gt 0 ]; then
	echo "$fallos fallo(s)."
	exit 1
fi
echo "Todas las recomendaciones salieron como se esperaba."
