#!/bin/sh
# Sube las ISO de una carpeta a SourceForge (área de descargas del
# proyecto), por rsync sobre SSH. Lo usa el flujo de GitHub Actions.
#
#   sh .github/subir-sourceforge.sh CARPETA_SF CARPETA_LOCAL
#
# CARPETA_SF: Ligera o Completa (dentro de /home/frs/project/PROYECTO), o
# Versiones/X.Y para una versión numerada (se crea si no existe).
# Con SF_SIN_REEMPLAZAR=1 (versiones numeradas) no se toca ningún archivo
# que ya esté en SourceForge con el mismo nombre.
# Variables: SF_USUARIO y SF_PROYECTO (del flujo) y SF_LLAVE, la llave
# privada SSH (secreto SOURCEFORGE_SSH_KEY del repositorio). Su parte
# pública va en https://sourceforge.net/auth/shell_services.
#
# Los archivos con el mismo nombre se reemplazan; los demás que haya en
# la carpeta de SourceForge (por ejemplo, ISO de otra versión de Alpine)
# no se tocan.

set -eu

destino="$1"
origen="$2"
: "${SF_USUARIO:?falta SF_USUARIO}"
: "${SF_PROYECTO:?falta SF_PROYECTO}"

if [ -z "${SF_LLAVE:-}" ]; then
	echo "::error::Falta el secreto SOURCEFORGE_SSH_KEY: no se puede subir a SourceForge."
	exit 1
fi

llave="$(mktemp)"
carpetas="$(mktemp -d)"
trap 'rm -rf "$llave" "$carpetas"' EXIT
# El secreto puede venir pegado con saltos de línea de Windows.
printf '%s\n' "$SF_LLAVE" | tr -d '\r' > "$llave"
chmod 600 "$llave"
mkdir -p "$HOME/.ssh"
ssh-keyscan -t rsa,ecdsa,ed25519 frs.sourceforge.net >> "$HOME/.ssh/known_hosts" 2>/dev/null

ls -l "$origen"
set --
[ "${SF_SIN_REEMPLAZAR:-}" != 1 ] || set -- --ignore-existing
# El rsync de SourceForge (3.1) no conoce --mkpath: las carpetas que
# falten (por ejemplo Versiones/X.Y) se crean antes copiando un árbol de
# carpetas vacías; las que ya existen no se tocan.
mkdir -p "$carpetas/$destino"
ssh_sf="ssh -i $llave -o BatchMode=yes -o ServerAliveInterval=30"
raiz="$SF_USUARIO@frs.sourceforge.net:/home/frs/project/$SF_PROYECTO"
# --partial: una subida cortada continúa donde quedó en el reintento.
intento=1
while :; do
	if rsync -r -e "$ssh_sf" "$carpetas"/ "$raiz/" \
		&& rsync -rtv --partial --chmod=F644 "$@" -e "$ssh_sf" \
			"$origen"/ "$raiz/$destino/"; then
		break
	fi
	if [ "$intento" -ge 4 ]; then
		echo "::error::No se pudo subir a SourceForge tras $intento intentos."
		exit 1
	fi
	sleep $((intento * 30))
	intento=$((intento + 1))
done
echo "Listo: https://sourceforge.net/projects/$SF_PROYECTO/files/$destino/"
