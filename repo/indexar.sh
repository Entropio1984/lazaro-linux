#!/bin/sh
# Junta los paquetes nuevos con los ya publicados y arma el índice firmado
# del repositorio de Lázaro (APKINDEX.tar.gz).
#
#   ./repo/indexar.sh CARPETA            En cualquier Linux con Docker.
#   ./repo/indexar.sh --dentro CARPETA   Lo que corre dentro del contenedor.
#
# CARPETA tiene los .apk publicados y los recién compilados mezclados. De
# cada paquete queda solo la versión más nueva; el resto se borra de la
# carpeta (el workflow borra de la Release lo que ya no está).

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$LAZARO_DIR/lib.sh"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" != "--dentro" ]; then
	[ -d "${1:-}" ] || die "uso: $0 CARPETA"
	CARPETA="$(cd "$1" && pwd)"
	exec docker run --rm \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR -e LAZARO_APK_KEY \
		-v "$LAZARO_DIR:/src:ro" \
		-v "$CARPETA:/repo" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/repo/indexar.sh --dentro /repo
fi

[ "$(id -u)" -eq 0 ] || die "--dentro debe ejecutarse como root"
D="${2:?falta la carpeta}"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
. "$LAZARO_DIR/repo/firma.sh"

# nombre-versión-rN.apk -> nombre
nombre() { echo "${1%.apk}" | sed 's/-[^-]*-r[0-9]*$//'; }
version() { a="${1%.apk}"; echo "${a#"$(nombre "$1")"-}"; }

ls "$D"/*.apk >/dev/null 2>&1 || die "no hay paquetes en $D"
for n in $(for a in "$D"/*.apk; do nombre "${a##*/}"; done | sort -u); do
	mejor=""
	for a in "$D/$n"-*.apk; do
		f="${a##*/}"
		[ "$(nombre "$f")" = "$n" ] || continue
		if [ -z "$mejor" ] || [ "$(apk version -t "$(version "$f")" "$(version "$mejor")")" = ">" ]; then
			mejor="$f"
		fi
	done
	for a in "$D/$n"-*.apk; do
		f="${a##*/}"
		[ "$(nombre "$f")" = "$n" ] && [ "$f" != "$mejor" ] || continue
		echo "  se retira $f"
		rm -f "$a"
	done
	echo "  $mejor"
done
rm -f "$D/APKINDEX.tar.gz"
firmar_indice "$D"
echo "FIRMA=$FIRMA"
[ "$FIRMA" = oficial ] || echo "AVISO: índice firmado con la clave de prueba (no se publica)."
