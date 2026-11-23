#!/bin/sh
# Copia la ISO Completa en el Google Drive de Julián, con rclone. Lo usa
# el flujo de GitHub Actions, después de la subida a SourceForge.
#
#   sh .github/subir-drive.sh CARPETA_DRIVE CARPETA_LOCAL
#
# CARPETA_DRIVE: carpeta dentro de "Lázaro Linux" en Drive (Completa).
# Variable: DRIVE_TOKEN, el permiso de Drive que entrega
# `rclone authorize` (secreto GDRIVE_TOKEN del repositorio). El permiso
# es de tipo "drive.file": rclone solo ve y toca lo que él mismo subió,
# nunca los demás archivos del Drive.
#
# La carpeta de Drive queda igual a CARPETA_LOCAL: la ISO nueva se sube y
# la anterior se borra (sin pasar por la papelera, que también ocupa
# espacio). La carpeta "Lázaro Linux" no cambia, así que su enlace
# compartido sigue sirviendo.
#
# Sin el secreto no hace nada: solo avisa.

set -eu

destino="$1"
origen="$2"
raiz="Lázaro Linux"

if [ -z "${DRIVE_TOKEN:-}" ]; then
	echo "::notice::Falta el secreto GDRIVE_TOKEN: no se sube a Google Drive."
	exit 0
fi

if ! command -v rclone >/dev/null 2>&1; then
	sudo apt-get update -qq
	sudo apt-get install -y -qq rclone
fi
rclone version | head -n 1

config="$(mktemp)"
trap 'rm -f "$config"' EXIT
# Se queda solo con lo que va entre llaves, por si se copió de más.
token="$(printf '%s' "$DRIVE_TOKEN" | tr -d '\r\n' | sed 's/^[^{]*//; s/[^}]*$//')"
case "$token" in
	"{"*"refresh_token"*"}") ;;
	*)
		echo "::error::El secreto GDRIVE_TOKEN no parece un permiso de rclone (debe empezar con { y tener refresh_token)."
		exit 1
		;;
esac
cat > "$config" <<EOF
[drive]
type = drive
scope = drive.file
token = $token
EOF
chmod 600 "$config"
export RCLONE_CONFIG="$config"

ls -l "$origen"
# Sin ISO no se sincroniza: una carpeta vacía borraría la de Drive.
if ! ls "$origen"/*.iso >/dev/null 2>&1; then
	echo "::error::No hay ninguna ISO en $origen: no se toca Google Drive."
	exit 1
fi
intento=1
while :; do
	# --drive-use-trash=false: la ISO vieja se borra de verdad (15 GB
	# gratis: la papelera también cuenta).
	if rclone sync "$origen" "drive:$raiz/$destino" \
		--drive-use-trash=false --drive-chunk-size 128M \
		--retries 3 --low-level-retries 20 --stats 1m --stats-one-line -v; then
		break
	fi
	if [ "$intento" -ge 3 ]; then
		echo "::error::No se pudo subir a Google Drive tras $intento intentos."
		exit 1
	fi
	sleep $((intento * 60))
	intento=$((intento + 1))
done

# Enlace público ("cualquier persona con el enlace puede ver") de la
# carpeta "Lázaro Linux". Si ya estaba compartida, es el mismo enlace.
if enlace="$(rclone link "drive:$raiz")"; then
	echo "Listo: $enlace"
	[ -z "${GITHUB_STEP_SUMMARY:-}" ] ||
		echo "Completa en Google Drive: $enlace" >> "$GITHUB_STEP_SUMMARY"
else
	echo "::warning::La ISO se subió, pero no se pudo crear el enlace público de la carpeta."
fi
