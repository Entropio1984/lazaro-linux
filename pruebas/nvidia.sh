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
	salida="$(LAZARO_ARCH=x86_64 sh "$PROG" --rama "$@")"
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

caso "RTX 3060 (Ampere)"          "propietario/abierto/actual/nvidia-open-src" moderna
caso "Turing/Ada/Blackwell igual" "propietario/abierto/actual/nvidia-open-src" moderna no
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
caso "dos modernas"               "propietario/abierto/actual/nvidia-open-src" moderna,moderna
caso "Maxwell y Pascal (580)"     "propietario/cerrado/580/"               maxwell,pascal
caso "Blackwell y Pascal"         "nouveau///"                             moderna,pascal
caso "RTX 3060 y GT 430 (Fermi)"  "nouveau///"                             "moderna fermi"

# Fuera de x86_64 (ISO de 32 bits) no hay controlador de NVIDIA.
eval "$(LAZARO_ARCH=x86 sh "$PROG" --rama moderna)"
n=$((n + 1))
if [ "$CONTROLADOR/$MOTIVO" = nouveau/solo-x86_64 ]; then echo "ok   $n 32 bits: nouveau"; else echo "FALLO $n 32 bits: $CONTROLADOR/$MOTIVO" >&2; fallos=$((fallos + 1)); fi

# Solo la combinación probada en hardware lleva ESTADO=probada.
eval "$(LAZARO_ARCH=x86_64 sh "$PROG" --rama moderna)"
n=$((n + 1))
if [ "$ESTADO" = probada ] && [ -n "$VERSION" ]; then echo "ok   $n moderna: probada y con versión"; else echo "FALLO $n moderna: ESTADO=$ESTADO VERSION=$VERSION" >&2; fallos=$((fallos + 1)); fi
eval "$(LAZARO_ARCH=x86_64 sh "$PROG" --rama kepler)"
n=$((n + 1))
if [ "$ESTADO" = sin-probar ]; then echo "ok   $n kepler: sin probar"; else echo "FALLO $n kepler: ESTADO=$ESTADO" >&2; fallos=$((fallos + 1)); fi

# La versión del paquete nvidia-open es la misma que la tabla.
eval "$(LAZARO_ARCH=x86_64 sh "$PROG" --rama moderna)"
pkgver=$(sed -n 's/^pkgver=//p' "$DIR/paquetes/nvidia-open/APKBUILD")
n=$((n + 1))
if [ "$pkgver" = "$VERSION" ]; then echo "ok   $n APKBUILD y tabla con la misma versión ($pkgver)"; else echo "FALLO $n APKBUILD $pkgver y tabla $VERSION" >&2; fallos=$((fallos + 1)); fi

# --activar y --desactivar en una raíz falsa (LAZARO_DESTINO): qué archivos
# deja y que desactivar vuelva a nouveau sin borrar el sysroot.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
dest="$TMP/sistema"
mkdir -p "$TMP/raiz/usr/bin" "$TMP/raiz/etc"
: > "$TMP/raiz/usr/bin/Xorg"; chmod +x "$TMP/raiz/usr/bin/Xorg"
echo "VERSION=$VERSION" > "$TMP/raiz/etc/lazaro-nvidia"
comprobar() { # NOMBRE CONDICION...
	nombre="$1"; shift
	n=$((n + 1))
	if "$@"; then echo "ok   $n $nombre"; else echo "FALLO $n $nombre" >&2; fallos=$((fallos + 1)); fi
}
if command -v zstd >/dev/null 2>&1; then
	tar -C "$TMP/raiz" -cf - . | zstd -q -o "$TMP/raiz.tar.zst"
	LAZARO_DESTINO="$dest" sh "$PROG" --activar "$TMP/raiz.tar.zst" >/dev/null
	comprobar "activar: descomprime el sysroot" [ -x "$dest/opt/lazaro-nvidia/raiz/usr/bin/Xorg" ]
else
	echo "(sin zstd: se prueba --activar con el sysroot ya puesto)"
	mkdir -p "$dest/opt/lazaro-nvidia"
	cp -a "$TMP/raiz" "$dest/opt/lazaro-nvidia/raiz"
	LAZARO_DESTINO="$dest" sh "$PROG" --activar >/dev/null
fi
comprobar "activar: servicio en el arranque" [ -L "$dest/etc/runlevels/default/lazaro-nvidia" ]
comprobar "activar: nvidia-raiz instalado" [ -x "$dest/usr/libexec/lazaro/nvidia-raiz" ]
comprobar "activar: LightDM usa el Xorg del sysroot" grep -q 'xserver-command=/usr/libexec/lazaro/nvidia-raiz xorg' "$dest/etc/lightdm/lightdm.conf.d/50-lazaro-nvidia.conf"
comprobar "activar: nouveau en la lista negra" grep -qx 'blacklist nouveau' "$dest/etc/modprobe.d/lazaro-nvidia.conf"
comprobar "activar: regla de udev" [ -f "$dest/etc/udev/rules.d/60-lazaro-nvidia.rules" ]
LAZARO_DESTINO="$dest" sh "$PROG" --desactivar >/dev/null
sin_rastro() {
	[ ! -e "$dest/etc/runlevels/default/lazaro-nvidia" ] &&
		[ ! -e "$dest/etc/lightdm/lightdm.conf.d/50-lazaro-nvidia.conf" ] &&
		[ ! -e "$dest/etc/modprobe.d/lazaro-nvidia.conf" ]
}
comprobar "desactivar: sin servicio ni LightDM ni lista negra" sin_rastro
comprobar "desactivar: el sysroot sigue" [ -x "$dest/opt/lazaro-nvidia/raiz/usr/bin/Xorg" ]
n=$((n + 1))
if LAZARO_DESTINO="$TMP/vacio" sh "$PROG" --activar >/dev/null 2>&1; then echo "FALLO $n activar sin sysroot no falla" >&2; fallos=$((fallos + 1)); else echo "ok   $n activar sin sysroot: falla"; fi

echo
if [ "$fallos" -eq 0 ]; then echo "Todo bien ($n casos)."; else echo "$fallos de $n casos fallaron." >&2; exit 1; fi
