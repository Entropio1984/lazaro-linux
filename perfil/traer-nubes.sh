#!/bin/sh
# Trae Lázaro Nubes (la aplicación de Julián para Google Drive, OneDrive
# y Dropbox) desde su propio repositorio de GitHub y la deja en CARPETA.
#
#   sh perfil/traer-nubes.sh CARPETA
#
# Lázaro no guarda una copia propia: igual que desktop-postinstall.sh, se
# descarga al compilar la última versión de la rama (sin fijar) y se
# anota qué commit era. Como queda dentro de la ISO, las dos ediciones
# (y la Completa sin internet) traen la aplicación en el USB.
#
# Variables:
#   NUBES_REPO    repositorio (por defecto el de config.env)
#   NUBES_RAMA    rama (por defecto main)
#   LAZARO_NUBES  carpeta con una copia local: se usa esa, sin descargar
#
# Se copian solo los archivos de la carpeta principal del repositorio
# (instalar.sh, nubes_*.py, README.md...), no sus subcarpetas.
# Al terminar escribe el commit en CARPETA/.commit.

set -eu

DEST="${1:?uso: traer-nubes.sh CARPETA}"
NUBES_REPO="${NUBES_REPO:-https://github.com/Entropio1984/lazaro-nubes}"
NUBES_RAMA="${NUBES_RAMA:-main}"

die() { printf 'traer-nubes: %s\n' "$*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "${LAZARO_NUBES:-}" ]; then
	[ -d "$LAZARO_NUBES" ] || die "no existe la carpeta $LAZARO_NUBES"
	echo "Lázaro Nubes: copia local $LAZARO_NUBES"
	origen="$LAZARO_NUBES"
	commit="${LAZARO_NUBES_COMMIT:-copia-local}"
else
	# La última versión de la rama, y se anota qué commit era. Con git
	# (hasta 3 intentos) y, si no hay git o no responde, el archivo
	# comprimido de la rama que da GitHub. Con tiempo límite: una conexión
	# colgada no deja la compilación esperando para siempre.
	commit=""
	if command -v git >/dev/null 2>&1; then
		echo "Lázaro Nubes: $NUBES_REPO (rama $NUBES_RAMA)"
		for intento in 1 2 3; do
			rm -rf "$tmp/x"
			if GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 \
				clone -q --depth 1 --branch "$NUBES_RAMA" "$NUBES_REPO" "$tmp/x"; then
				commit="$(git -C "$tmp/x" rev-parse --short=12 HEAD 2>/dev/null)" || commit=desconocido
				origen="$tmp/x"
				break
			fi
			echo "Lázaro Nubes: falló la descarga con git (intento $intento de 3)" >&2
			[ "$intento" = 3 ] || sleep 10
		done
	fi
	if [ -z "$commit" ]; then
		url="${NUBES_REPO%/}"
		url="${url%.git}/archive/refs/heads/$NUBES_RAMA.tar.gz"
		echo "Lázaro Nubes: $url"
		curl -fsSL --retry 3 --connect-timeout 30 --max-time 600 -o "$tmp/nubes.tar.gz" "$url" ||
			die "no se pudo descargar $url"
		rm -rf "$tmp/x"
		mkdir "$tmp/x"
		tar -xzf "$tmp/nubes.tar.gz" -C "$tmp/x" || die "el archivo descargado está dañado"
		origen="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
		[ -n "$origen" ] || die "el archivo descargado está vacío"
		commit=desconocido
	fi
fi

# Lo mínimo para que el botón "Nubes" funcione.
for f in instalar.sh nubes_rclone.py nubes_bandeja.py nubes_sinc.py nubes_tema.py; do
	[ -f "$origen/$f" ] && [ ! -L "$origen/$f" ] || die "falta $f en Lázaro Nubes"
done
sh -n "$origen/instalar.sh" || die "instalar.sh de Lázaro Nubes tiene errores de sintaxis"

rm -rf "$DEST"
mkdir -p "$DEST"
for f in "$origen"/*; do
	# Solo archivos normales: un enlace podría apuntar fuera de la
	# descarga (por ejemplo a la llave que firma los paquetes).
	[ ! -L "$f" ] || { echo "Lázaro Nubes: se omite el enlace $(basename "$f")" >&2; continue; }
	[ -f "$f" ] || continue
	case "$f" in *.pyc | *.tmp) continue ;; esac
	cp "$f" "$DEST/"
done
chmod 755 "$DEST/instalar.sh" "$DEST/nubes_rclone.py" "$DEST/nubes_bandeja.py" "$DEST/nubes_sinc.py"
chmod 644 "$DEST/nubes_tema.py"
printf '%s\n' "$commit" > "$DEST/.commit"
echo "Lázaro Nubes: commit $commit ($(ls "$DEST" | wc -l) archivos)"
