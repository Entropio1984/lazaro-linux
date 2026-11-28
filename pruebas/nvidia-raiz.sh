#!/bin/sh
# Prueba live/usr/share/lazaro/nvidia/nvidia-raiz sin tarjeta: con un
# /proc falso, qué /dev/nvidia* crea (lo que haría nvidia-modprobe).
#
#   pruebas/nvidia-raiz.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/share/lazaro/nvidia/nvidia-raiz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mknod falso: anota "NOMBRE MAYOR MENOR" y crea un archivo vacío.
cat > "$TMP/mknod" <<'EOT'
#!/bin/sh
# mknod -m 666 RUTA c MAYOR MENOR
echo "${3##*/} $5 $6" >> "$LAZARO_ANOTADOS"
: > "$3"
EOT
chmod +x "$TMP/mknod"

fallos=0
n=0

# caso NOMBRE "ESPERADO" GPUS UVM
#   GPUS: cuántas tarjetas hay en /proc/driver/nvidia/gpus (o "sin" si el
#   módulo no está cargado); UVM: mayor de nvidia-uvm, o vacío.
caso() {
	nombre="$1" esperado="$2" gpus="$3" uvm="$4"
	p="$TMP/$n/proc" d="$TMP/$n/dev"
	mkdir -p "$p" "$d"
	printf 'Character devices:\n  1 mem\n195 nvidia\n' > "$p/devices"
	[ -z "$uvm" ] || echo "$uvm nvidia-uvm" >> "$p/devices"
	if [ "$gpus" != sin ]; then
		i=0
		while [ $i -lt "$gpus" ]; do mkdir -p "$p/driver/nvidia/gpus/0000:0$i:00.0"; i=$((i + 1)); done
	fi
	: > "$TMP/$n/anotados"
	LAZARO_PROC="$p" LAZARO_DEV="$d" LAZARO_MKNOD="$TMP/mknod" LAZARO_ANOTADOS="$TMP/$n/anotados" \
		sh "$PROG" dispositivos
	# Una segunda vez no crea nada más.
	LAZARO_PROC="$p" LAZARO_DEV="$d" LAZARO_MKNOD="$TMP/mknod" LAZARO_ANOTADOS="$TMP/$n/anotados" \
		sh "$PROG" dispositivos
	obtenido="$(tr '\n' ';' < "$TMP/$n/anotados")"
	n=$((n + 1))
	if [ "$obtenido" = "$esperado" ]; then
		echo "ok   $n $nombre"
	else
		echo "FALLO $n $nombre: se esperaba '$esperado' y salió '$obtenido'" >&2
		fallos=$((fallos + 1))
	fi
}

caso "sin el módulo cargado" "" sin ""
caso "una tarjeta, sin nvidia-uvm" "nvidia0 195 0;nvidiactl 195 255;nvidia-modeset 195 254;" 1 ""
caso "una tarjeta con nvidia-uvm" "nvidia0 195 0;nvidiactl 195 255;nvidia-modeset 195 254;nvidia-uvm 509 0;nvidia-uvm-tools 509 1;" 1 509
caso "dos tarjetas" "nvidia0 195 0;nvidia1 195 1;nvidiactl 195 255;nvidia-modeset 195 254;" 2 ""

# El uso sin argumentos devuelve 2.
n=$((n + 1))
if sh "$PROG" >/dev/null 2>&1; then echo "FALLO $n sin argumentos no falla" >&2; fallos=$((fallos + 1)); else echo "ok   $n sin argumentos: uso"; fi

echo
if [ "$fallos" -eq 0 ]; then echo "Todo bien ($n casos)."; else echo "$fallos de $n casos fallaron." >&2; exit 1; fi
