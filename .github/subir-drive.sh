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
# La carpeta de Drive queda igual a CARPETA_LOCAL: la ISO anterior se
# borra (sin pasar por la papelera, que también ocupa espacio) y se sube
# la nueva. La carpeta "Lázaro Linux" la crea rclone y no cambia, así que
# su enlace compartido sigue sirviendo. No hay que crearla a mano: con el
# permiso drive.file rclone no vería una carpeta hecha desde la web y
# crearía otra con el mismo nombre.
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
# Las versiones nuevas de rclone entregan el permiso codificado (un texto
# largo de letras, tipo eyJ0b2tlbiI6...) y las viejas como {...}. Se
# aceptan las dos, aunque se haya copiado de más ("Paste the following",
# "<---End paste"). Nunca se imprime el permiso.
token="$(printf '%s' "$DRIVE_TOKEN" | python3 -I -c '
import base64, json, re, sys
texto = sys.stdin.read().replace("\r", "").replace("\n", "")
def es_token(t):
    try:
        return "refresh_token" in json.loads(t)
    except Exception:
        return False
llaves = re.search(r"\{.*\}", texto)
if llaves and es_token(llaves.group(0)):
    print(llaves.group(0))
    sys.exit(0)
for blob in sorted(re.findall(r"[A-Za-z0-9_\-+/=]{20,}", texto), key=len, reverse=True):
    try:
        datos = json.loads(base64.urlsafe_b64decode(blob.replace("+", "-").replace("/", "_").rstrip("=") + "=="))
    except Exception:
        continue
    t = datos.get("token") if isinstance(datos, dict) else None
    if isinstance(t, dict):
        t = json.dumps(t)
    if isinstance(t, str) and es_token(t):
        print(t)
        sys.exit(0)
sys.exit(1)
')" || {
	echo "::error::El secreto GDRIVE_TOKEN no parece un permiso de rclone: vuelve a copiar lo que aparece entre \"Paste the following\" y \"<---End paste\"."
	exit 1
}
cat > "$config" <<EOF
[drive]
type = drive
scope = drive.file
token = $token
EOF
chmod 600 "$config"
export RCLONE_CONFIG="$config"

ls -l "$origen"
# Sin ISO no se toca Drive: se borraría la ISO de allá sin subir otra.
if ! ls "$origen"/*.iso >/dev/null 2>&1; then
	echo "::error::No hay ninguna ISO en $origen: no se toca Google Drive."
	exit 1
fi
# Primero se borra lo que haya en la carpeta de Drive y después se sube
# lo nuevo. Así nunca hacen falta dos ISO de espacio a la vez, y Drive no
# guarda versiones viejas de la ISO (reemplazar un archivo con el mismo
# nombre deja la versión anterior ocupando espacio hasta 30 días).
# --drive-use-trash=false: se borra de verdad (la papelera también
# ocupa). Mientras sube (unos minutos) la carpeta queda vacía.
rclone mkdir "drive:$raiz/$destino"
rclone delete "drive:$raiz/$destino" --drive-use-trash=false -v
intento=1
while :; do
	if rclone copy "$origen" "drive:$raiz/$destino" \
		--drive-chunk-size 128M \
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
