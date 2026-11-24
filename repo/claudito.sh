#!/bin/sh
# Arma Quickshell y lazaro-claudito (Claudito Shell Fusion, la barra de
# Sway) para el repositorio de Lázaro, firmados como el resto.
#
#   ./repo/claudito.sh            En cualquier Linux con Docker.
#   ./repo/claudito.sh --dentro   Lo que corre dentro del contenedor.
#
# QS_REL: número de la versión de Quickshell (pkgrel). Quickshell usa
# partes internas de Qt y hay que recompilarlo cada vez que Alpine cambia
# Qt: el flujo "Repositorio Lázaro" sube este número en cada recompilación
# para que los equipos lo actualicen. Resultado: salida/claudito/x86_64/ y
# salida/claudito/resumen.txt (FIRMA, QT, versiones).
# LAZARO_REL: el pkgrel de lazaro-claudito (en GitHub, la cantidad de
# cambios de lazaro-linux, como lazaro-herramientas).

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$LAZARO_DIR/lib.sh"
SALIDA="${SALIDA:-$LAZARO_DIR/salida/claudito}"
QS_REL="${QS_REL:-0}"
LAZARO_REL="${LAZARO_REL:-0}"

msg() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" != "--dentro" ]; then
	mkdir -p "$SALIDA"
	exec docker run --rm \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR -e LAZARO_APK_KEY -e QS_REL -e LAZARO_REL \
		-e SALIDA=/salida \
		-v "$LAZARO_DIR:/src:ro" \
		-v "$SALIDA:/salida" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/repo/claudito.sh --dentro
fi

[ "$(id -u)" -eq 0 ] || die "--dentro debe ejecutarse como root"
[ "$ALPINE_ARCH" = x86_64 ] || die "Quickshell y Claudito son solo de 64 bits"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
apk update -q
. "$LAZARO_DIR/repo/firma.sh"

REPO="$CASA/repo-claudito"
for pq in quickshell lazaro-claudito; do
	T="$CASA/$pq"
	rm -rf "$T"
	cp -r "$LAZARO_DIR/paquetes/$pq" "$T"
	case "$pq" in
		quickshell) sed -i "s/^pkgrel=.*/pkgrel=$QS_REL/" "$T/APKBUILD" ;;
		lazaro-claudito) sed -i "s/^pkgrel=.*/pkgrel=$LAZARO_REL/" "$T/APKBUILD" ;;
	esac
	chown -R constructor:abuild "$T"
	msg "Armando $pq"
	if ! su constructor -c "cd $T && REPODEST=$REPO abuild -r" > "$CASA/abuild-$pq.log" 2>&1; then
		sed -n '/Uninstalling dependencies/q;p' "$CASA/abuild-$pq.log" | tail -n 80 >&2
		die "falló el armado de $pq"
	fi
done

rm -rf "${SALIDA:?}/$ALPINE_ARCH"
mkdir -p "$SALIDA/$ALPINE_ARCH"
cp "$REPO"/*/"$ALPINE_ARCH"/quickshell-[0-9]*.apk "$REPO"/*/"$ALPINE_ARCH"/lazaro-claudito-[0-9]*.apk "$SALIDA/$ALPINE_ARCH/"
firmar_indice "$SALIDA/$ALPINE_ARCH"

QS_APK="$(ls "$SALIDA/$ALPINE_ARCH"/quickshell-[0-9]*.apk)"
QT="$(tar -xzOf "$QS_APK" usr/share/quickshell/qt-version 2>/dev/null)" || QT=""
[ -n "$QT" ] || die "Quickshell no anotó con qué Qt se compiló"

# Prueba: se instala con el índice firmado, como en un equipo, y
# Quickshell arranca (sin pantalla solo muestra su versión).
cp "$LLAVES/$NOMBRE.pub" /etc/apk/keys/
apk add -q --repository "$SALIDA/$ALPINE_ARCH" lazaro-claudito
qs --version
[ -x /usr/bin/lazaro-claudito ] && [ -f /etc/sway/config.d/60-lazaro-claudito.conf ] ||
	die "lazaro-claudito no dejó su programa o su configuración de Sway"

{
	echo "FIRMA=$FIRMA"
	echo "QT=$QT"
	for a in "$SALIDA/$ALPINE_ARCH"/*.apk; do
		echo "PAQUETE=${a##*/} $(du -k "$a" | cut -f1) KB"
	done
	echo "INSTALADO=$(du -sk /usr/share/lazaro/claudito /usr/share/icons/Reversal-blue /usr/share/icons/Reversal-blue-dark /usr/bin/qs 2>/dev/null | awk '{s += $1} END {print int(s / 1024)}') MB"
} > "$SALIDA/resumen.txt"
cat "$SALIDA/resumen.txt"
chmod -R a+rX "$SALIDA"
msg "Listo: $SALIDA"
