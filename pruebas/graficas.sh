#!/bin/sh
# Prueba las decisiones de live/usr/sbin/lazaro-graficas sin hardware:
# arma un /sys falso con las tarjetas de cada caso y un lspci falso que
# devuelve el nombre del chip. Las pruebas en QEMU no tienen NVIDIA, así
# que esta es la única forma automática de recorrer cada camino.
#
#   pruebas/graficas.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-graficas"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# lspci falso: "lspci -mm -s RANURA" responde con el nombre guardado en
# $TMP/nombres/RANURA.
mkdir -p "$TMP/bin" "$TMP/nombres"
cat > "$TMP/bin/lspci" <<'EOF'
#!/bin/sh
nombre="$(cat "$LAZARO_NOMBRES/$3" 2>/dev/null || echo "Device 0000")"
printf '%s "VGA compatible controller" "Fabricante" "%s" "" ""\n' "$3" "$nombre"
EOF
chmod +x "$TMP/bin/lspci"
export LAZARO_NOMBRES="$TMP/nombres"

fallos=0

# caso NOMBRE ESPERADO "LINEA DE ARRANQUE" CHASIS TARJETA...
#   TARJETA: RANURA:FABRICANTE:PRINCIPAL[:NOMBRE DEL CHIP]
#   CHASIS: 3 escritorio, 10 portátil
caso() {
	nombre="$1"; esperado="$2"; cmdline="$3"; chasis="$4"
	shift 4
	sys="$TMP/$nombre/sys"
	rm -rf "$TMP/$nombre" "$TMP/nombres"/*
	mkdir -p "$sys/bus/pci/devices" "$sys/class/dmi/id"
	echo "$chasis" > "$sys/class/dmi/id/chassis_type"
	for t in "$@"; do
		ranura="${t%%:*}"; resto="${t#*:}"
		fab="${resto%%:*}"; resto="${resto#*:}"
		princ="${resto%%:*}"
		chip=""
		case "$resto" in *:*) chip="${resto#*:}" ;; esac
		d="$sys/bus/pci/devices/0000:$ranura"
		mkdir -p "$d"
		echo 0x030000 > "$d/class"
		echo "$fab" > "$d/vendor"
		echo "$princ" > "$d/boot_vga"
		[ -z "$chip" ] || echo "$chip" > "$TMP/nombres/0000:$ranura"
	done
	echo "$cmdline" > "$TMP/$nombre/cmdline"
	salida="$(PATH="$TMP/bin:$PATH" LAZARO_SYS="$sys" LAZARO_CMDLINE="$TMP/$nombre/cmdline" \
		LAZARO_GRAFICAS="$TMP/$nombre/graficas" sh "$PROG" --sin-cargar)"
	obtenido="$(sed -n 's/^DECISION=//p' "$TMP/$nombre/graficas")/$(sed -n 's/^MOTIVO=//p' "$TMP/$nombre/graficas")"
	if [ "$obtenido" = "$esperado" ]; then
		echo "OK    $nombre: $obtenido"
	else
		echo "FALLO $nombre: se esperaba $esperado y salió $obtenido ($salida)"
		fallos=$((fallos + 1))
	fi
}

N=0x10de; I=0x8086
caso sin-nvidia          sin-nvidia/sin-nvidia "" 3  "00.02.0:$I:1"
caso k53sv-optimus-fermi activa/optimus        "" 10 "00.02.0:$I:1" "01.00.0:$N:0:GF108M [GeForce GT 540M]"
caso pc-solo-fermi       activa/generacion     "" 3  "01.00.0:$N:1:GF119 [GeForce GT 520]"
caso pc-solo-tesla       activa/generacion     "" 3  "01.00.0:$N:1:GT218 [GeForce 210]"
caso pc-solo-kepler      activa/generacion     "" 3  "01.00.0:$N:1:GK107 [GeForce GT 640]"
caso pc-solo-turing      activa/generacion     "" 3  "01.00.0:$N:1:TU116 [GeForce GTX 1660]"
caso pc-desconocida      seguro/generacion     "" 3  "01.00.0:$N:1"
caso portatil-solo-nv    activa/generacion     "" 10 "01.00.0:$N:1:G86M [GeForce 8400M GS]"
caso cq50-8200m          activa/generacion     "" 10 "02.00.0:$N:1:C77 [GeForce 8200M G]"
caso dos-nvidia-tesla    activa/generacion     "" 3  "01.00.0:$N:1:GA106 [GeForce RTX 3060]" "02.00.0:$N:0:G96 [GeForce 9500 GT]"
caso dos-nvidia          activa/generacion     "" 3  "01.00.0:$N:1:GK107 [GeForce GT 640]" "02.00.0:$N:0:GA106 [GeForce RTX 3060]"
caso dos-nvidia-fermi    activa/generacion     "" 3  "01.00.0:$N:1:GA106 [GeForce RTX 3060]" "02.00.0:$N:0:GF108 [GeForce GT 430]"
caso forzar-activa       activa/elegido        "quiet lazaro.nvidia=activa" 3 "01.00.0:$N:1:GF119 [GeForce GT 520]"
caso forzar-seguro       seguro/elegido        "lazaro.nvidia=seguro" 10 "00.02.0:$I:1" "01.00.0:$N:0:TU117M [GeForce GTX 1650 Mobile]"
caso nomodeset           seguro/nomodeset      "nomodeset lazaro.nvidia=activa" 3 "01.00.0:$N:1:TU116 [GeForce GTX 1660]"

if [ "$fallos" -gt 0 ]; then
	echo "$fallos caso(s) fallaron."
	exit 1
fi
echo "Todas las decisiones de lazaro-graficas son las esperadas."
