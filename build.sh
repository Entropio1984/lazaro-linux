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
# Edición Completa (todo para instalar sin internet, unos 4,5 GB):
#   LAZARO_EDICION=completa LAZARO_FLATPAK_USB=/ruta/flatpak-usb ./build.sh
#   LAZARO_FLATPAK_USB: repositorio de Flatpak con OnlyOffice y Brave (lo
#   prepara el flujo de GitHub Actions). Sin él, esas aplicaciones se
#   descargan de Flathub después del primer arranque, como en la Ligera.
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
	# Sello de compilación (va a /usr/share/lazaro/version.env y lo muestra
	# lazaro-diagnostico): de qué código y cuándo salió esta ISO.
	if [ -z "${LAZARO_COMMIT:-}" ]; then
		LAZARO_COMMIT="$(git -C "$LAZARO_DIR" rev-parse --short=12 HEAD 2>/dev/null)" || LAZARO_COMMIT=""
		if [ -z "$LAZARO_COMMIT" ]; then
			LAZARO_COMMIT=desconocido
		elif [ -n "$(git -C "$LAZARO_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
			LAZARO_COMMIT="$LAZARO_COMMIT+cambios-locales"
		fi
	fi
	LAZARO_FECHA="${LAZARO_FECHA:-$(date -u '+%Y-%m-%d %H:%M UTC')}"
	export LAZARO_COMMIT LAZARO_FECHA
	msg "Compilando en alpine:$ALPINE_DOCKER_TAG (Alpine $ALPINE_BRANCH)"
	# Copia local del script (opcional): se monta dentro del contenedor.
	set --
	if [ -n "${LAZARO_SCRIPT:-}" ]; then
		set -- -v "$(realpath "$LAZARO_SCRIPT"):/postinstall.sh:ro" -e LAZARO_SCRIPT=/postinstall.sh
	fi
	if [ -n "${LAZARO_FLATPAK_USB:-}" ]; then
		set -- "$@" -v "$(realpath "$LAZARO_FLATPAK_USB"):/flatpak-usb:ro" -e LAZARO_FLATPAK_USB=/flatpak-usb
	fi
	exec docker run --rm "$@" \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR \
		-e CALAMARES_VERSION -e ISO_VERSION -e POSTINSTALL_URL -e LAZARO_EDICION \
		-e LAZARO_COMMIT -e LAZARO_FECHA -e LAZARO_CANAL -e LAZARO_SCRIPT_COMMIT \
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

# --- broadcom-wl (driver wifi privativo de Broadcom) --------------------
# Va como código (broadcom-wl-src) y lo compila akms en el equipo que lo
# necesita. Ver paquetes/broadcom-wl/APKBUILD.
WL_VER=$(sed -n 's/^pkgver=//p' "$LAZARO_DIR/paquetes/broadcom-wl/APKBUILD")
WL_REL=$(sed -n 's/^pkgrel=//p' "$LAZARO_DIR/paquetes/broadcom-wl/APKBUILD")
if ls "$REPO_PROPIO/paquetes/$ALPINE_ARCH/broadcom-wl-src-$WL_VER-r$WL_REL.apk" >/dev/null 2>&1; then
	msg "broadcom-wl $WL_VER ya está empaquetado (caché)"
else
	msg "Empaquetando broadcom-wl $WL_VER"
	rm -f "$REPO_PROPIO/paquetes/$ALPINE_ARCH"/broadcom-wl-src-*.apk
	cd "$TRABAJO/paquetes/broadcom-wl"
	if grep -q '^sha512sums=""' APKBUILD; then
		su constructor -c "abuild checksum"
		echo "AVISO: fija esta suma en paquetes/broadcom-wl/APKBUILD:"
		grep -A2 '^sha512sums' APKBUILD
	fi
	REGISTRO="$CACHE/abuild-broadcom-wl.log"
	if ! su constructor -c "REPODEST=$REPO_PROPIO abuild -r" > "$REGISTRO" 2>&1; then
		echo "Últimas líneas útiles de $REGISTRO:" >&2
		sed -n '/Uninstalling dependencies/q;p' "$REGISTRO" | tail -n 60 >&2
		die "falló el empaquetado de broadcom-wl"
	fi
	tail -n 5 "$REGISTRO"
fi
cd "$LAZARO_DIR"

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
LAZARO_EDICION="$LAZARO_EDICION"
EOF
chown -R constructor:abuild "$CONSTRUCTOR_HOME"

# --- desktop-postinstall.sh ---------------------------------------------
SCRIPT="$CONSTRUCTOR_HOME/desktop-postinstall.sh"
if [ -n "${LAZARO_SCRIPT:-}" ]; then
	msg "Usando desktop-postinstall.sh local: $LAZARO_SCRIPT"
	cp "$LAZARO_SCRIPT" "$SCRIPT"
	LAZARO_SCRIPT_COMMIT="${LAZARO_SCRIPT_COMMIT:-copia-local}"
else
	msg "Descargando desktop-postinstall.sh"
	# Se sigue tomando la última versión de la rama (sin fijar), pero se
	# anota qué commit era: se lee el commit de la rama en ese momento y
	# se descarga justo ese. Si no se puede, se usa la URL tal cual.
	script_url="$POSTINSTALL_URL"
	LAZARO_SCRIPT_COMMIT=desconocido
	case "$POSTINSTALL_URL" in
	https://raw.githubusercontent.com/*/*/*/*)
		s_resto="${POSTINSTALL_URL#https://raw.githubusercontent.com/}"
		s_dueno="${s_resto%%/*}"; s_resto="${s_resto#*/}"
		s_repo="${s_resto%%/*}"; s_resto="${s_resto#*/}"
		s_rama="${s_resto%%/*}"; s_archivo="${s_resto#*/}"
		s_commit="$(git ls-remote "https://github.com/$s_dueno/$s_repo" "refs/heads/$s_rama" 2>/dev/null | cut -c1-40)" || s_commit=""
		case "$s_commit" in
		*[!0-9a-f]* | "") ;;
		*)
			if [ "${#s_commit}" -eq 40 ]; then
				script_url="https://raw.githubusercontent.com/$s_dueno/$s_repo/$s_commit/$s_archivo"
				LAZARO_SCRIPT_COMMIT="$(printf '%s' "$s_commit" | cut -c1-12)"
			fi
			;;
		esac
		;;
	esac
	echo "Script: $script_url"
	curl -fsSL --retry 3 -o "$SCRIPT" "$script_url"
fi
sh -n "$SCRIPT" || die "desktop-postinstall.sh tiene errores de sintaxis"
chown constructor:abuild "$SCRIPT"
# Con build.sh --dentro directo (sin Docker) nadie los calculó antes.
if [ -z "${LAZARO_COMMIT:-}" ]; then
	LAZARO_COMMIT="$(git -C "$LAZARO_DIR" rev-parse --short=12 HEAD 2>/dev/null)" || LAZARO_COMMIT=""
fi
LAZARO_FECHA="${LAZARO_FECHA:-$(date -u '+%Y-%m-%d %H:%M UTC')}"
cat >> "$CONSTRUCTOR_HOME/version.env" <<EOF
LAZARO_CANAL="${LAZARO_CANAL:-local}"
LAZARO_FECHA="$LAZARO_FECHA"
LAZARO_COMMIT="${LAZARO_COMMIT:-desconocido}"
LAZARO_SCRIPT_COMMIT="$LAZARO_SCRIPT_COMMIT"
LAZARO_SCRIPT_SHA256="$(sha256sum "$SCRIPT" | cut -c1-64)"
EOF
msg "Sello de compilación"
cat "$CONSTRUCTOR_HOME/version.env"

# --- Edición Completa ----------------------------------------------------
PAQUETES_COMPLETA="$CONSTRUCTOR_HOME/paquetes-completa.txt"
rm -f "$PAQUETES_COMPLETA"
if [ "$LAZARO_EDICION" = completa ]; then
	msg "Edición Completa: lista de paquetes para instalar sin internet"
	INDICES="$CONSTRUCTOR_HOME/indices"
	mkdir -p "$INDICES"
	curl -fsSL --retry 3 -o "$INDICES/main.tar.gz" "$ALPINE_REPO_MAIN/$ALPINE_ARCH/APKINDEX.tar.gz"
	curl -fsSL --retry 3 -o "$INDICES/community.tar.gz" "$ALPINE_REPO_COMMUNITY/$ALPINE_ARCH/APKINDEX.tar.gz"
	# Las listas del perfil (LAZARO_LIVE, LAZARO_DESTINO...).
	perfil_paquetes=$(LAZARO_DIR="$LAZARO_DIR" sh -c '. "$LAZARO_DIR/perfil/mkimg.lazaro.sh"
		echo $LAZARO_LIVE $LAZARO_DESTINO $LAZARO_EXTRAS $LAZARO_ESCRITORIOS $LAZARO_COMPLETA')
	# shellcheck disable=SC2086
	sh "$LAZARO_DIR/perfil/paquetes-completa.sh" "$PAQUETES_COMPLETA" "$SCRIPT" \
		"$INDICES/main.tar.gz" "$INDICES/community.tar.gz" \
		"$REPO_PROPIO/paquetes/$ALPINE_ARCH/APKINDEX.tar.gz" -- $perfil_paquetes
	chown constructor:abuild "$PAQUETES_COMPLETA"
	if [ -d "${LAZARO_FLATPAK_USB:-}/repo" ]; then
		msg "Aplicaciones de Flathub para el USB: $(du -sh "$LAZARO_FLATPAK_USB" | cut -f1) ($(cat "$LAZARO_FLATPAK_USB/aplicaciones" 2>/dev/null | tr '\n' ' '))"
	else
		echo "AVISO: sin LAZARO_FLATPAK_USB; OnlyOffice y Brave se descargarán después del primer arranque."
	fi
fi

# --- Datos de hardware para lazaro-controladores -------------------------
# Se generan al compilar y entran en la sesión live (genapkovl los copia).
DATOS_HW="$CONSTRUCTOR_HOME/datos-hardware"
rm -rf "$DATOS_HW"
mkdir -p "$DATOS_HW/usr/share/lazaro/firmware-licencia/ipw2x00"
msg "Datos de hardware: lectores de huellas y firmware de Intel 2100/2200"
# Lectores de huellas que reconoce libfprint (de su tabla de udev), como
# "vvvv:pppp" para compararlos con los USB conectados.
t_hw="$(mktemp -d)"
apk fetch -q --stdout libfprint | tar -xz -C "$t_hw"
grep -rhoiE 'usb:v[0-9a-f]{4}p[0-9a-f]{4}' "$t_hw" | tr 'A-F' 'a-f' |
	sed 's/^usb:v\(....\)p\(....\)$/\1:\2/' | sort -u \
	> "$DATOS_HW/usr/share/lazaro/huellas.ids"
rm -rf "$t_hw"
[ -s "$DATOS_HW/usr/share/lazaro/huellas.ids" ] || die "no se encontraron lectores de huellas en libfprint"
echo "  lectores de huellas: $(wc -l < "$DATOS_HW/usr/share/lazaro/huellas.ids")"
# Firmware de Intel PRO/Wireless 2100/2200 (paquete de Debian). Su licencia
# permite repartirlo junto con ella; se instala solo si el usuario la acepta.
# Versión fija de Debian 13 (estable; queda en el servidor por años) con su
# suma: si el archivo no es exactamente ese, no se usa. Se sacan del
# paquete solo los 6 firmware y la licencia.
IPW_DEB="https://deb.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/firmware-ipw2x00_20250410-2_all.deb"
IPW_SHA256="a0351412176598056d18982d905aa9605b6250bfb16c316fa773c6716868db56"
IPW_ARCHIVOS="./usr/lib/firmware/ipw2100-1.3.fw ./usr/lib/firmware/ipw2100-1.3-i.fw
	./usr/lib/firmware/ipw2100-1.3-p.fw ./usr/lib/firmware/ipw2200-bss.fw
	./usr/lib/firmware/ipw2200-ibss.fw ./usr/lib/firmware/ipw2200-sniffer.fw
	./usr/share/doc/firmware-ipw2x00/copyright"
t_hw="$(mktemp -d)"
ipw_d="$DATOS_HW/usr/share/lazaro/firmware-licencia"
# shellcheck disable=SC2086
if curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 -o "$t_hw/ipw.deb" "$IPW_DEB" &&
	[ "$(sha256sum "$t_hw/ipw.deb" | cut -c1-64)" = "$IPW_SHA256" ] &&
	(cd "$t_hw" && ar x ipw.deb && mkdir d && tar -xf data.tar.* -C d $IPW_ARCHIVOS); then
	cp "$t_hw"/d/usr/lib/firmware/ipw2*.fw "$ipw_d/ipw2x00/"
	cp "$t_hw/d/usr/share/doc/firmware-ipw2x00/copyright" "$ipw_d/LICENSE.ipw2x00"
	echo "  firmware de Intel: $(basename "$IPW_DEB") ($(ls "$ipw_d/ipw2x00" | wc -l) archivos)"
else
	# Sin firmware ni licencia, lazaro-controladores no ofrece estas tarjetas.
	echo "AVISO: no se pudo obtener $(basename "$IPW_DEB") (o su suma no coincide); la ISO va sin el firmware de Intel 2100/2200."
	rm -rf "$ipw_d"
fi
rm -rf "$t_hw"
chown -R constructor:abuild "$DATOS_HW"

# --- ISO ----------------------------------------------------------------
msg "Generando la ISO"
mkdir -p "$SALIDA"
chown constructor:abuild "$SALIDA"
su constructor -c "cd $CONSTRUCTOR_HOME && \
	LAZARO_DIR='$LAZARO_DIR' \
	LAZARO_LIVE_DIR='$LAZARO_DIR/live' \
	LAZARO_DATOS_HW='$DATOS_HW' \
	LAZARO_SCRIPT='$SCRIPT' \
	LAZARO_VERSION_ENV='$CONSTRUCTOR_HOME/version.env' \
	LAZARO_PUBKEY='$LLAVE.pub' \
	LAZARO_EDICION='$LAZARO_EDICION' \
	LAZARO_PAQUETES_COMPLETA='$PAQUETES_COMPLETA' \
	LAZARO_FLATPAK_USB='${LAZARO_FLATPAK_USB:-}' \
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
