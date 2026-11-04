#!/bin/sh
# Prueba las reglas de live/usr/sbin/lazaro-controladores sin hardware:
# arma un /sys falso, un modules.alias, unos avisos del kernel (dmesg) y
# un apk falso que dice qué paquetes ya están instalados. Así se recorre
# cada regla (impresoras, huellas, wifi viejo, firmware faltante...).
#
#   pruebas/controladores.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-controladores"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# apk falso: "apk [--root R] info -e PAQUETE" responde según
# $LAZARO_PRUEBA_INSTALADOS (un paquete por línea).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/apk" <<'EOS'
#!/bin/sh
for ultimo in "$@"; do :; done
grep -qx "$ultimo" "$LAZARO_PRUEBA_INSTALADOS" 2>/dev/null
EOS
chmod +x "$TMP/bin/apk"
PATH="$TMP/bin:$PATH"

# Datos: los de la ISO más una lista corta de lectores de huellas.
mkdir -p "$TMP/datos"
cp "$DIR/live/usr/share/lazaro/firmware-paquetes.tsv" "$TMP/datos/"
printf '%s\n' 06cb:00bd 138a:0097 > "$TMP/datos/huellas.ids"

cat > "$TMP/modules.alias" <<'EOS'
# Aliases tomados de modules.alias de linux-lts (forma real).
alias pci:v000014E4d00004318sv*sd*bc*sc*i* b43
alias pci:v000014E4d00004311sv*sd*bc*sc*i* b43
alias pci:v000014E4d00004301sv*sd*bc*sc*i* b43legacy
alias pci:v00008086d00004220sv*sd*bc*sc*i* ipw2200
alias pci:v00008086d00001043sv*sd*bc*sc*i* ipw2100
alias pci:v00008086d00009DC8sv*sd*bc*sc*i* snd_sof_pci_intel_cnl
alias pci:v00001260d00003890sv*sd*bc*sc*i* p54pci
alias usb:v0CF3p9271d*dc*dsc*dp*ic*isc*ip*in* ath9k_htc
alias usb:v04B8p*d*dc*dsc*dp*ic07isc*ip*in* usblp
EOS

fallos=0
n=0

# caso NOMBRE "DEBE TENER" "NO DEBE TENER" [VAR=valor...]
#   Arma el equipo con las funciones de abajo antes de llamar.
#   DEBE TENER: claves (columna 2) separadas por espacios.
caso() {
	nombre="$1"; si="$2"; no="$3"; shift 3
	n=$((n + 1))
	salida="$(env LAZARO_SYS="$SYS" LAZARO_MODULOS="$TMP/modules.alias" \
		LAZARO_DMESG="$TMP/dmesg" LAZARO_CMDLINE="$TMP/cmdline" \
		LAZARO_DATOS="$TMP/datos" LAZARO_PRUEBA_INSTALADOS="$TMP/instalados" \
		LAZARO_CONTROLADORES_LOG="$TMP/log" "$@" \
		sh "$PROG" --revisar --raiz "$RAIZ" 2>"$TMP/err")" || {
		echo "FALLO $nombre: terminó con error"; cat "$TMP/err"; fallos=$((fallos + 1)); return 0; }
	claves=" $(printf '%s\n' "$salida" | cut -f2 | tr '\n' ' ')"
	mal=""
	for c in $si; do
		case "$claves" in *" $c "*) ;; *) mal="$mal falta:$c" ;; esac
	done
	for c in $no; do
		case "$claves" in *" $c "*) mal="$mal sobra:$c" ;; esac
	done
	if [ -n "$mal" ]; then
		echo "FALLO $nombre:$mal"
		echo "  salida:$claves"
		fallos=$((fallos + 1))
	else
		echo "ok    $nombre"
	fi
}

# Equipo vacío: sin piezas, sin avisos, nada instalado.
nuevo() {
	SYS="$TMP/sys"; RAIZ="$TMP/raiz"
	rm -rf "$SYS" "$RAIZ"
	mkdir -p "$SYS/bus/pci/devices" "$SYS/bus/usb/devices" "$SYS/class/power_supply" "$RAIZ"
	: > "$TMP/dmesg"; : > "$TMP/cmdline"; : > "$TMP/instalados"
}
pci() { # RANURA FABRICANTE DISPOSITIVO (hex de 4)
	d="$SYS/bus/pci/devices/$1"; mkdir -p "$d"
	echo "0x$2" > "$d/vendor"; echo "0x$3" > "$d/device"
	echo "pci:v0000$(echo "$2" | tr a-f A-F)d0000$(echo "$3" | tr a-f A-F)sv00001028sd00000007bc02sc80i00" > "$d/modalias"
}
usb() { # PUERTO FABRICANTE PRODUCTO CLASE_DE_INTERFAZ
	d="$SYS/bus/usb/devices/$1"; mkdir -p "$d" "$d:1.0"
	echo "$2" > "$d/idVendor"; echo "$3" > "$d/idProduct"
	echo "$4" > "$d:1.0/bInterfaceClass"
	echo "usb:v$(echo "$2" | tr a-f A-F)p$(echo "$3" | tr a-f A-F)d0100dc00dsc00dp00ic$4isc01ip02in00" > "$d:1.0/modalias"
}
bateria() { mkdir -p "$SYS/class/power_supply/BAT0"; echo Battery > "$SYS/class/power_supply/BAT0/type"; }
instalados() { printf '%s\n' "$@" >> "$TMP/instalados"; }

SIEMPRE="escaneres celulares tabletas discos temperatura"

nuevo
caso "escritorio sin nada especial" "$SIEMPRE firmware braille" "bateria sonido-sof huellas b43 tarjetas"

nuevo
instalados sane sane-airscan simple-scan gvfs-mtp gvfs-gphoto2 gvfs-afc xf86-input-wacom libwacom ntfs-3g exfatprogs mtools lm-sensors
caso "lo de siempre ya instalado" "firmware" "$SIEMPRE"

nuevo
mkdir -p "$RAIZ/etc/lazaro"; : > "$RAIZ/etc/lazaro/sin-escritorio"
caso "sin escritorio: nada gráfico" "discos temperatura" "escaneres celulares tabletas"

nuevo
bateria
pci 0000:00:1f.3 8086 9dc8
usb 1-1 03f0 1234 07
usb 1-2 06cb 00bd ff
caso "portátil: batería, sonido SOF, impresora HP, huellas" "bateria sonido-sof impresora-hp huellas" "impresora-otra"

nuevo
usb 1-1 04b8 0001 07
usb 1-2 0bda 0165 0b
caso "impresora Epson y lector de tarjetas" "impresora-epson tarjetas" "impresora-hp impresora-otra"

nuevo
pci 0000:02:00.0 14e4 4318
caso "Broadcom b43" "b43" "b43legacy"

nuevo
pci 0000:02:00.0 14e4 4311
caso "Broadcom con wl: no pide b43" "" "b43"

nuevo
pci 0000:02:00.0 14e4 4318
mkdir -p "$RAIZ/lib/firmware/b43"; : > "$RAIZ/lib/firmware/b43/ucode5.fw"
caso "b43 con firmware ya puesto" "" "b43"

nuevo
pci 0000:02:00.0 14e4 4301
caso "Broadcom b43legacy" "b43legacy" "b43"

nuevo
pci 0000:02:02.0 8086 4220
caso "Intel 2200 pide licencia" "ipw2200" "ipw2100"

nuevo
pci 0000:02:02.0 8086 4220
mkdir -p "$RAIZ/etc/lazaro"; echo ipw2200=rechazado > "$RAIZ/etc/lazaro/controladores.conf"
caso "Intel 2200 rechazada: no se vuelve a ofrecer" "" "ipw2200"

nuevo
pci 0000:02:02.0 8086 1043
caso "Intel 2100" "ipw2100" "ipw2200"

nuevo
pci 0000:02:00.0 1260 3890
caso "Prism54 PCI" "p54pci" ""

nuevo
cat > "$TMP/dmesg" <<'EOS'
[    5.1] iwlwifi 0000:03:00.0: Direct firmware load for iwlwifi-7260-17.ucode failed with error -2
[    5.2] bluetooth hci0: firmware: failed to load rtl_bt/rtl8723b_fw.bin (-2)
[    5.3] b43-phy0 ERROR: Direct firmware load for b43/ucode15.fw failed with error -2
EOS
caso "firmware que el kernel no encontró" "firmware-linux-firmware-intel firmware-linux-firmware-rtl_bt" "b43"

nuevo
echo "quiet lazaro.controladores=b43,ipw2200,huellas,tarjetas" > "$TMP/cmdline"
caso "simulado por parámetro de arranque (QEMU)" "b43 ipw2200 huellas tarjetas" ""

nuevo
bateria
caso "solo lo automático: sin cosas de menú" "bateria" "firmware braille" SOLO_AUTOMATICO=si

# Saca data.tar.* de un .deb sin la orden ar (busybox no la trae).
n=$((n + 1))
mkdir -p "$TMP/deb/x/usr/lib/firmware" "$TMP/deb/o"
echo prueba > "$TMP/deb/x/usr/lib/firmware/ipw2200-bss.fw"
echo 2.0 > "$TMP/deb/debian-binary"
# Partes de tamaño impar a propósito: ar las rellena con un byte.
printf 'xyz' > "$TMP/deb/control.tar.gz"
tar -czf "$TMP/deb/data.tar.gz" -C "$TMP/deb/x" .
{
	printf '!<arch>\n'
	for f in debian-binary control.tar.gz data.tar.gz; do
		t="$(wc -c < "$TMP/deb/$f")"
		printf '%-16s%-12s%-6s%-6s%-8s%-10s`\n' "$f" 0 0 0 100644 "$t"
		cat "$TMP/deb/$f"
		[ $((t % 2)) = 0 ] || printf '\n'
	done
} > "$TMP/deb/p.deb"
if (cd "$TMP/deb/o" && sed -n '/^sacar_data_tar()/,/^}/p' "$PROG" > f.sh && . ./f.sh \
	&& sacar_data_tar ../p.deb && tar -xzf data.tar.gz && grep -qx prueba usr/lib/firmware/ipw2200-bss.fw); then
	echo "ok    sacar el firmware de un .deb"
else
	echo "FALLO sacar el firmware de un .deb"; fallos=$((fallos + 1))
fi

echo "$((n - fallos)) de $n casos bien."
[ "$fallos" = 0 ]
