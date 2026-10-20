#!/bin/sh
# Compila la ISO de Lázaro Linux.
#
#   ./build.sh            En cualquier Linux con Docker: abre un contenedor
#                         Alpine de la versión de config.env y compila dentro.
#   ./build.sh --dentro   Lo que corre dentro del contenedor (o en un Alpine
#                         de verdad, como root).
#
# Resultado: salida/lazaro-linux-<versión>-<alpine>-x86_64.iso
# Caché (Calamares ya compilado y su llave de firma): cache/
#
# Para otra versión de Alpine: ALPINE_BRANCH=edge ./build.sh
# Con una copia local de desktop-postinstall.sh:
#   LAZARO_SCRIPT=../alpine-desktop-setup/desktop-postinstall.sh ./build.sh

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$LAZARO_DIR/lib.sh"

SALIDA="${SALIDA:-$LAZARO_DIR/salida}"
CACHE="${CACHE:-$LAZARO_DIR/cache}"

msg() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" != "--dentro" ]; then
	mkdir -p "$SALIDA" "$CACHE"
	msg "Compilando en alpine:$ALPINE_DOCKER_TAG (Alpine $ALPINE_BRANCH)"
	# Copia local del script (opcional): se monta dentro del contenedor.
	set --
	if [ -n "${LAZARO_SCRIPT:-}" ]; then
		set -- -v "$(realpath "$LAZARO_SCRIPT"):/postinstall.sh:ro" -e LAZARO_SCRIPT=/postinstall.sh
	fi
	exec docker run --rm "$@" \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR \
		-e CALAMARES_VERSION -e ISO_VERSION -e POSTINSTALL_URL \
		-e SALIDA=/salida -e CACHE=/cache \
		-v "$LAZARO_DIR:/src:ro" \
		-v "$SALIDA:/salida" \
		-v "$CACHE:/cache" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/build.sh --dentro
fi

[ "$(id -u)" -eq 0 ] || die "build.sh --dentro debe ejecutarse como root"

msg "Preparando el entorno de compilación"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
apk update
apk add alpine-sdk alpine-conf apk-tools busybox fakeroot syslinux xorriso \
	squashfs-tools mtools grub grub-efi dosfstools git curl

# abuild no compila como root: se usa un usuario del grupo abuild.
id constructor >/dev/null 2>&1 || adduser -D -G abuild constructor
CONSTRUCTOR_HOME=/home/constructor
mkdir -p "$CACHE/llaves" "$CACHE/paquetes/$ALPINE_BRANCH"
chown -R constructor:abuild "$CACHE"

# Llave de firma del repositorio propio (Calamares e índice de la ISO).
# Se guarda en la caché para que los paquetes ya compilados sigan siendo
# válidos. Se crea con openssl directamente (como hace abuild-keygen)
# porque la carpeta de configuración de abuild cambió entre versiones
# (~/.abuild en 3.24, ~/.config/abuild en edge).
LLAVE="$CACHE/llaves/lazaro-linux.rsa"
if [ ! -f "$LLAVE" ]; then
	msg "Creando la llave de firma"
	openssl genrsa -out "$LLAVE" 2048
	openssl rsa -in "$LLAVE" -pubout -out "$LLAVE.pub"
fi
for d in "$CONSTRUCTOR_HOME/.abuild" "$CONSTRUCTOR_HOME/.config/abuild"; do
	mkdir -p "$d"
	cp "$LLAVE" "$LLAVE.pub" "$d/"
	echo "PACKAGER_PRIVKEY=\"$d/lazaro-linux.rsa\"" > "$d/abuild.conf"
done
cp "$LLAVE.pub" /etc/apk/keys/
chown -R constructor:abuild "$CONSTRUCTOR_HOME" "$CACHE"

# --- Calamares ----------------------------------------------------------
REPO_PROPIO="$CACHE/paquetes/$ALPINE_BRANCH"
TRABAJO="$CONSTRUCTOR_HOME/trabajo"
rm -rf "$TRABAJO"
mkdir -p "$TRABAJO"
cp -r "$LAZARO_DIR/paquetes" "$TRABAJO/"
chown -R constructor:abuild "$TRABAJO"

# Un Calamares de la caché sirve solo si sus dependencias siguen
# existiendo en los repositorios actuales de Alpine (por ejemplo, tras
# subir de versión Qt o kpmcore). Si no, se vuelve a compilar.
if ls "$REPO_PROPIO/paquetes/$ALPINE_ARCH/calamares-$CALAMARES_VERSION-"*.apk >/dev/null 2>&1 &&
	! apk add --simulate --quiet --repository "$REPO_PROPIO/paquetes" calamares >/dev/null 2>&1; then
	msg "El Calamares de la caché ya no encaja con los paquetes actuales de Alpine; se recompila"
	rm -f "$REPO_PROPIO/paquetes/$ALPINE_ARCH"/calamares-*.apk
fi

if ls "$REPO_PROPIO/paquetes/$ALPINE_ARCH/calamares-$CALAMARES_VERSION-"*.apk >/dev/null 2>&1; then
	msg "Calamares $CALAMARES_VERSION ya está compilado (caché)"
else
	msg "Compilando Calamares $CALAMARES_VERSION (tarda varios minutos)"
	cd "$TRABAJO/paquetes/calamares"
	if grep -q '^sha512sums=""' APKBUILD; then
		# Primera compilación de una versión nueva: se calcula la suma y se
		# muestra para fijarla en el APKBUILD del repositorio.
		su constructor -c "CALAMARES_VERSION=$CALAMARES_VERSION abuild checksum"
		echo "AVISO: fija esta suma en paquetes/calamares/APKBUILD:"
		grep -A2 '^sha512sums' APKBUILD
	fi
	# La salida completa va a un archivo; si falla, se muestra lo que
	# importa (abuild borra cientos de dependencias después del error y
	# eso entierra el mensaje).
	REGISTRO="$CACHE/abuild-calamares.log"
	if ! su constructor -c "CALAMARES_VERSION=$CALAMARES_VERSION REPODEST=$REPO_PROPIO abuild -r" \
		> "$REGISTRO" 2>&1; then
		echo "Últimas líneas útiles de $REGISTRO:" >&2
		sed -n '/Uninstalling dependencies/q;p' "$REGISTRO" | tail -n 80 >&2
		die "falló la compilación de Calamares"
	fi
	tail -n 5 "$REGISTRO"
fi

# --- aports/scripts (mkimage.sh) ---------------------------------------
msg "Descargando aports/scripts de la rama $APORTS_BRANCH"
APORTS="$CONSTRUCTOR_HOME/aports"
rm -rf "$APORTS"
su constructor -c "git clone --quiet --depth 1 --filter=blob:none --sparse \
	-b $APORTS_BRANCH https://github.com/alpinelinux/aports.git $APORTS \
	&& git -C $APORTS sparse-checkout set scripts"

mkdir -p "$CONSTRUCTOR_HOME/.mkimage"
cp "$LAZARO_DIR"/perfil/mkimg.lazaro.sh "$LAZARO_DIR"/perfil/genapkovl-lazaro.sh \
	"$CONSTRUCTOR_HOME/.mkimage/"
cat > "$CONSTRUCTOR_HOME/version.env" <<EOF
ALPINE_BRANCH="$ALPINE_BRANCH"
ALPINE_MIRROR="$ALPINE_MIRROR"
ISO_VERSION="$ISO_VERSION"
CALAMARES_VERSION="$CALAMARES_VERSION"
LAZARO_LLAVE="$(basename "$LLAVE").pub"
EOF
chown -R constructor:abuild "$CONSTRUCTOR_HOME"

# --- desktop-postinstall.sh ---------------------------------------------
SCRIPT="$CONSTRUCTOR_HOME/desktop-postinstall.sh"
if [ -n "${LAZARO_SCRIPT:-}" ]; then
	msg "Usando desktop-postinstall.sh local: $LAZARO_SCRIPT"
	cp "$LAZARO_SCRIPT" "$SCRIPT"
else
	msg "Descargando desktop-postinstall.sh"
	curl -fsSL --retry 3 -o "$SCRIPT" "$POSTINSTALL_URL"
fi
sh -n "$SCRIPT" || die "desktop-postinstall.sh tiene errores de sintaxis"
chown constructor:abuild "$SCRIPT"

# --- ISO ----------------------------------------------------------------
msg "Generando la ISO"
mkdir -p "$SALIDA"
chown constructor:abuild "$SALIDA"
su constructor -c "cd $CONSTRUCTOR_HOME && \
	LAZARO_DIR='$LAZARO_DIR' \
	LAZARO_LIVE_DIR='$LAZARO_DIR/live' \
	LAZARO_SCRIPT='$SCRIPT' \
	LAZARO_VERSION_ENV='$CONSTRUCTOR_HOME/version.env' \
	LAZARO_PUBKEY='$LLAVE.pub' \
	sh $APORTS/scripts/mkimage.sh \
		--tag '$ISO_VERSION' \
		--outdir '$SALIDA' \
		--workdir '$CONSTRUCTOR_HOME/mkimage-trabajo' \
		--arch '$ALPINE_ARCH' \
		--repository '$ALPINE_REPO_MAIN' \
		--repository '$ALPINE_REPO_COMMUNITY' \
		--repository '$REPO_PROPIO/paquetes' \
		--profile lazaro"

ISO_GENERADA="$SALIDA/lazaro-linux-$ISO_VERSION-$ALPINE_ARCH.iso"
[ -f "$ISO_GENERADA" ] || die "No se generó la ISO"
mv "$ISO_GENERADA" "$SALIDA/$ISO_FILE"
(cd "$SALIDA" && sha256sum "$ISO_FILE" > "$ISO_FILE.sha256")
msg "Listo: $SALIDA/$ISO_FILE ($(du -h "$SALIDA/$ISO_FILE" | cut -f1))"
