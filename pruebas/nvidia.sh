#!/bin/sh
# Prueba la tabla de live/usr/sbin/lazaro-nvidia: qué controlador le toca
# a cada generación de NVIDIA (docs/nvidia/ARQUITECTURA.md, sección 3).
#
#   pruebas/nvidia.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-nvidia"

fallos=0
n=0

# caso NOMBRE "ESPERADO" GENERACION [OPTIMUS]
#   ESPERADO: CONTROLADOR/MODULO/RAMA/PAQUETE
caso() {
	nombre="$1" esperado="$2"; shift 2
	salida="$(sh "$PROG" --rama "$@")"
	CONTROLADOR="" MODULO="" RAMA="" PAQUETE=""
	eval "$salida"
	obtenido="$CONTROLADOR/$MODULO/$RAMA/$PAQUETE"
	n=$((n + 1))
	if [ "$obtenido" = "$esperado" ]; then
		echo "ok   $n $nombre"
	else
		echo "FALLO $n $nombre: se esperaba '$esperado' y salió '$obtenido'" >&2
		fallos=$((fallos + 1))
	fi
}

caso "RTX 3060 (Ampere)"          "propietario/abierto/actual/nvidia-open" moderna
caso "Turing/Ada/Blackwell igual" "propietario/abierto/actual/nvidia-open" moderna no
caso "GTX 1060 (Pascal)"          "propietario/cerrado/580/"               pascal
caso "GTX 970 (Maxwell)"          "propietario/cerrado/580/"               maxwell
caso "Titan V (Volta)"            "propietario/cerrado/580/"               volta
caso "GT 740 (Kepler)"            "propietario/cerrado/470/"               kepler
caso "GT 540M (Fermi)"            "nouveau///"                             fermi
caso "GeForce 8 (Tesla)"          "nouveau///"                             tesla
caso "anteriores a las GeForce 8" "nouveau///"                             anterior
caso "no identificada"            "nouveau///"                             desconocida
caso "portátil Optimus moderno"   "nouveau///"                             moderna si
caso "sin NVIDIA"                 "ninguno///"                             ninguna

# Solo la combinación probada en hardware lleva ESTADO=probada.
eval "$(sh "$PROG" --rama moderna)"
n=$((n + 1))
if [ "$ESTADO" = probada ] && [ -n "$VERSION" ]; then echo "ok   $n moderna: probada y con versión"; else echo "FALLO $n moderna: ESTADO=$ESTADO VERSION=$VERSION" >&2; fallos=$((fallos + 1)); fi
eval "$(sh "$PROG" --rama kepler)"
n=$((n + 1))
if [ "$ESTADO" = sin-probar ]; then echo "ok   $n kepler: sin probar"; else echo "FALLO $n kepler: ESTADO=$ESTADO" >&2; fallos=$((fallos + 1)); fi

# La versión del paquete nvidia-open es la misma que la tabla.
eval "$(sh "$PROG" --rama moderna)"
pkgver=$(sed -n 's/^pkgver=//p' "$DIR/paquetes/nvidia-open/APKBUILD")
n=$((n + 1))
if [ "$pkgver" = "$VERSION" ]; then echo "ok   $n APKBUILD y tabla con la misma versión ($pkgver)"; else echo "FALLO $n APKBUILD $pkgver y tabla $VERSION" >&2; fallos=$((fallos + 1)); fi

echo
if [ "$fallos" -eq 0 ]; then echo "Todo bien ($n casos)."; else echo "$fallos de $n casos fallaron." >&2; exit 1; fi
