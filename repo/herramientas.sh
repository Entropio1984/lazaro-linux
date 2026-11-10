#!/bin/sh
# Arma el paquete lazaro-herramientas con los programas de Lázaro que van
# al sistema instalado, firmado como el resto del repositorio de Lázaro.
#
#   ./repo/herramientas.sh            En cualquier Linux con Docker.
#   ./repo/herramientas.sh --dentro   Lo que corre dentro del contenedor.
#
# LAZARO_REL: número de la versión del paquete (pkgrel). En GitHub es la
# cantidad de cambios de lazaro-linux, así cada cambio es una
# actualización. Resultado: salida/herramientas/x86_64/.

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$LAZARO_DIR/lib.sh"
SALIDA="${SALIDA:-$LAZARO_DIR/salida/herramientas}"
LAZARO_REL="${LAZARO_REL:-0}"

msg() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" != "--dentro" ]; then
	mkdir -p "$SALIDA"
	exec docker run --rm \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR -e LAZARO_APK_KEY -e LAZARO_REL \
		-e SALIDA=/salida \
		-v "$LAZARO_DIR:/src:ro" \
		-v "$SALIDA:/salida" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/repo/herramientas.sh --dentro
fi

[ "$(id -u)" -eq 0 ] || die "--dentro debe ejecutarse como root"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
apk update -q
. "$LAZARO_DIR/repo/firma.sh"

msg "Armando lazaro-herramientas $ISO_VERSION-r$LAZARO_REL"
T="$CASA/lazaro-herramientas"
rm -rf "$T"
cp -r "$LAZARO_DIR/paquetes/lazaro-herramientas" "$T"
A="$T/archivos"
L="$LAZARO_DIR/live"
# Los programas van en /usr/local/sbin (donde los deja lazaro-instalar y
# los buscan los servicios), pero abuild no acepta paquetes con archivos
# ahí: el paquete los trae en /usr/share/lazaro/programas y el
# post-install los copia. Lo de /etc, igual: apk no reemplaza archivos de
# /etc que ya existen (los equipos instalados antes del paquete los
# tienen sueltos).
for p in lazaro-diagnostico lazaro-controladores lazaro-afinador lazaro-kernel lazaro-repositorio \
	lazaro-bienvenida lazaro-flatpak lazaro-actualizador; do
	install -Dm755 "$L/usr/sbin/$p" "$A/usr/share/lazaro/programas/$p"
done
for f in lazaro-controladores.initd lazaro-afinador.initd lazaro-kernel.initd; do
	install -Dm755 "$L/usr/share/lazaro/$f" "$A/usr/share/lazaro/$f"
done
install -Dm644 "$L/usr/share/lazaro/firmware-paquetes.tsv" "$A/usr/share/lazaro/firmware-paquetes.tsv"
install -Dm644 "$L/usr/share/applications/lazaro-controladores.desktop" "$A/usr/share/applications/lazaro-controladores.desktop"
install -Dm644 "$L/usr/share/lazaro/lazaro-afinador.desktop" "$A/usr/share/applications/lazaro-afinador.desktop"
install -Dm644 "$L/etc/xdg/autostart/lazaro-controladores.desktop" "$A/usr/share/lazaro/lazaro-controladores-sesion.desktop"
# Bienvenida: botones (un archivo por función), menú, icono y arranque
# con la sesión.
cp -r "$L/usr/share/lazaro/bienvenida" "$A/usr/share/lazaro/"
install -Dm644 "$L/usr/share/applications/lazaro-bienvenida.desktop" "$A/usr/share/applications/lazaro-bienvenida.desktop"
install -Dm644 "$L/usr/share/lazaro/lazaro-bienvenida-sesion.desktop" "$A/usr/share/lazaro/lazaro-bienvenida-sesion.desktop"
# Con la ruta completa: hay sesiones gráficas que no traen
# /usr/local/sbin en el PATH y no encontrarían el programa.
sed -i 's|^Exec=lazaro-bienvenida|Exec=/usr/local/sbin/lazaro-bienvenida|' \
	"$A/usr/share/applications/lazaro-bienvenida.desktop" \
	"$A/usr/share/lazaro/lazaro-bienvenida-sesion.desktop"
grep -q '^Exec=/usr/local/sbin/lazaro-bienvenida --sesion$' "$A/usr/share/lazaro/lazaro-bienvenida-sesion.desktop" ||
	die "el arranque de la Bienvenida no quedó con la ruta completa"
for t in 64x64 256x256; do
	install -Dm644 "$L/usr/share/icons/hicolor/$t/apps/lazaro-bienvenida.png" "$A/usr/share/icons/hicolor/$t/apps/lazaro-bienvenida.png"
done
install -Dm644 "$LAZARO_DIR/repo/lazaro.rsa.pub" "$A/usr/share/lazaro/lazaro.rsa.pub"
[ ! -e "$A/etc" ] && [ ! -e "$A/usr/local" ] || die "el paquete no debe llevar archivos en /etc ni en /usr/local"
# Lectores de huellas que reconoce libfprint (igual que build.sh).
t="$(mktemp -d)"
apk fetch -q --stdout libfprint | tar -xz -C "$t"
grep -rhoiE 'usb:v[0-9a-f]{4}p[0-9a-f]{4}' "$t" | tr 'A-F' 'a-f' |
	sed 's/^usb:v\(....\)p\(....\)$/\1:\2/' | sort -u > "$A/usr/share/lazaro/huellas.ids"
rm -rf "$t"
[ -s "$A/usr/share/lazaro/huellas.ids" ] || die "no se encontraron lectores de huellas en libfprint"
chown -R constructor:abuild "$T"

REPO="$CASA/repo-herramientas"
if ! su constructor -c "cd $T && LAZARO_VER=$ISO_VERSION LAZARO_REL=$LAZARO_REL REPODEST=$REPO abuild -r" > "$CASA/abuild-herramientas.log" 2>&1; then
	tail -n 60 "$CASA/abuild-herramientas.log" >&2
	die "falló el armado de lazaro-herramientas"
fi
rm -rf "${SALIDA:?}/$ALPINE_ARCH"
mkdir -p "$SALIDA/$ALPINE_ARCH"
cp "$REPO"/*/"$ALPINE_ARCH"/lazaro-herramientas-"$ISO_VERSION"-r"$LAZARO_REL".apk "$SALIDA/$ALPINE_ARCH/" ||
	die "no se encontró el paquete armado"
firmar_indice "$SALIDA/$ALPINE_ARCH"
echo "FIRMA=$FIRMA" > "$SALIDA/resumen.txt"
echo "VERSION=$ISO_VERSION-r$LAZARO_REL" >> "$SALIDA/resumen.txt"
tar -tzf "$SALIDA/$ALPINE_ARCH/lazaro-herramientas-$ISO_VERSION-r$LAZARO_REL.apk" | grep -v '^\.' | sed 's/^/  /' >> "$SALIDA/resumen.txt"
cat "$SALIDA/resumen.txt"
chmod -R a+rX "$SALIDA"
msg "Listo: $SALIDA"
