#!/bin/sh
# Compila el kernel Lázaro (paquete linux-lazaro) a partir del linux-lts de
# Alpine de la versión de config.env: mismo código y parches, la misma
# configuración más kernel/lazaro.fragment.
#
#   ./kernel/compilar.sh            En cualquier Linux con Docker.
#   ./kernel/compilar.sh --dentro   Lo que corre dentro del contenedor.
#
# Resultado en salida/kernel/ (un repositorio de apk listo para publicar):
#   x86_64/linux-lazaro-<versión>.apk, x86_64/linux-lazaro-dev-<versión>.apk
#   x86_64/APKINDEX.tar.gz (firmado), lazaro-kernel.rsa.pub, resumen.txt
#
# Firma: con la clave privada de la variable LAZARO_APK_KEY (el secreto de
# GitHub). Su mitad pública tiene que ser kernel/lazaro-kernel.rsa.pub, la
# que llevan la ISO y los equipos instalados. Sin LAZARO_APK_KEY se firma
# con una clave de prueba: sirve para probar, nunca para publicar.

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$LAZARO_DIR/lib.sh"
. "$LAZARO_DIR/kernel/version"

SALIDA="${SALIDA:-$LAZARO_DIR/salida/kernel}"

msg() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" != "--dentro" ]; then
	mkdir -p "$SALIDA"
	exec docker run --rm \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR -e LAZARO_APK_KEY \
		-e SALIDA=/salida \
		-v "$LAZARO_DIR:/src:ro" \
		-v "$SALIDA:/salida" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/kernel/compilar.sh --dentro
fi

[ "$(id -u)" -eq 0 ] || die "--dentro debe ejecutarse como root"

msg "Preparando el entorno (Alpine $ALPINE_BRANCH)"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
apk update
apk add alpine-sdk git openssl

id constructor >/dev/null 2>&1 || adduser -D -G abuild constructor
CASA=/home/constructor

# --- Clave de firma --------------------------------------------------------
LLAVES="$CASA/.llaves"
mkdir -p "$LLAVES"
if [ -n "${LAZARO_APK_KEY:-}" ]; then
	NOMBRE=lazaro-kernel.rsa
	printf '%s\n' "$LAZARO_APK_KEY" > "$LLAVES/$NOMBRE"
	openssl rsa -in "$LLAVES/$NOMBRE" -pubout -out "$LLAVES/$NOMBRE.pub" 2>/dev/null ||
		die "LAZARO_APK_KEY no es una clave RSA válida"
	if [ -f "$LAZARO_DIR/kernel/lazaro-kernel.rsa.pub" ] &&
		! cmp -s "$LLAVES/$NOMBRE.pub" "$LAZARO_DIR/kernel/lazaro-kernel.rsa.pub"; then
		die "LAZARO_APK_KEY no corresponde a kernel/lazaro-kernel.rsa.pub: los equipos rechazarían el kernel"
	fi
	FIRMA=oficial
else
	NOMBRE=lazaro-kernel-prueba.rsa
	openssl genrsa -out "$LLAVES/$NOMBRE" 2048 2>/dev/null
	openssl rsa -in "$LLAVES/$NOMBRE" -pubout -out "$LLAVES/$NOMBRE.pub" 2>/dev/null
	FIRMA=prueba
	echo "AVISO: sin LAZARO_APK_KEY; se firma con una clave de prueba (no publicar)."
fi
chmod 600 "$LLAVES/$NOMBRE"
for d in "$CASA/.abuild" "$CASA/.config/abuild"; do
	mkdir -p "$d"
	echo "PACKAGER_PRIVKEY=\"$LLAVES/$NOMBRE\"" > "$d/abuild.conf"
	echo "JOBS=$(nproc)" >> "$d/abuild.conf"
	echo "MAKEFLAGS=-j$(nproc)" >> "$d/abuild.conf"
done
cp "$LLAVES/$NOMBRE.pub" /etc/apk/keys/
chown -R constructor:abuild "$CASA"

# --- linux-lts de aports -----------------------------------------------------
msg "Descargando main/linux-lts de aports ($APORTS_BRANCH)"
APORTS="$CASA/aports"
rm -rf "$APORTS"
su constructor -c "git clone --quiet --depth 1 --filter=blob:none --sparse \
	-b $APORTS_BRANCH https://github.com/alpinelinux/aports.git $APORTS \
	&& git -C $APORTS sparse-checkout set main/linux-lts"
K="$APORTS/main/linux-lts"
[ -f "$K/APKBUILD" ] && [ -f "$K/lts.$ALPINE_ARCH.config" ] || die "no se encontró linux-lts en aports"

pkgver=$(sed -n 's/^pkgver=//p' "$K/APKBUILD")
pkgrel_alpine=$(sed -n 's/^pkgrel=//p' "$K/APKBUILD")
pkgrel=$((pkgrel_alpine * 100 + KERNEL_REV))
sed -i "s/^pkgrel=.*/pkgrel=$pkgrel/" "$K/APKBUILD"
msg "linux-lazaro $pkgver-r$pkgrel (linux-lts $pkgver-r$pkgrel_alpine de Alpine + revisión $KERNEL_REV)"

# Configuración: la de Alpine y encima la de Lázaro.
{
	cat "$K/lts.$ALPINE_ARCH.config"
	echo
	cat "$LAZARO_DIR/kernel/lazaro.fragment"
} > "$K/lazaro.$ALPINE_ARCH.config"
chown -R constructor:abuild "$K"

cd "$K"
su constructor -c "FLAVOR=lazaro abuild checksum"

msg "Compilando (puede tardar más de una hora)"
REPO="$CASA/repo"
REGISTRO="$CASA/abuild-kernel.log"
if ! su constructor -c "cd $K && FLAVOR=lazaro REPODEST=$REPO abuild -r" > "$REGISTRO" 2>&1; then
	echo "Últimas líneas útiles de la compilación:" >&2
	sed -n '/Uninstalling dependencies/q;p' "$REGISTRO" | tail -n 80 >&2
	die "falló la compilación del kernel"
fi
tail -n 5 "$REGISTRO"


# --- Repositorio para publicar -----------------------------------------------
msg "Armando el repositorio"
rm -rf "${SALIDA:?}/$ALPINE_ARCH"
mkdir -p "$SALIDA/$ALPINE_ARCH"
cp "$REPO"/main/"$ALPINE_ARCH"/linux-lazaro-"$pkgver"-r"$pkgrel".apk \
	"$REPO"/main/"$ALPINE_ARCH"/linux-lazaro-dev-"$pkgver"-r"$pkgrel".apk \
	"$SALIDA/$ALPINE_ARCH/" || die "no se encontraron los paquetes compilados"
cd "$SALIDA/$ALPINE_ARCH"
apk index --quiet -o APKINDEX.tar.gz --rewrite-arch "$ALPINE_ARCH" \
	-d "Kernel Lázaro para Alpine $ALPINE_BRANCH" ./*.apk
cp APKINDEX.tar.gz "$CASA/APKINDEX.tar.gz"
chown constructor:abuild "$CASA/APKINDEX.tar.gz"
su constructor -c "abuild-sign -k $LLAVES/$NOMBRE $CASA/APKINDEX.tar.gz" >/dev/null
cp "$CASA/APKINDEX.tar.gz" APKINDEX.tar.gz
cp "$LLAVES/$NOMBRE.pub" "$SALIDA/"
# Las opciones que de verdad quedaron (olddefconfig puede haber cambiado
# alguna por dependencias): las trae el paquete en /boot.
CONFIG_FINAL="$SALIDA/config-lazaro"
tar -xzOf "$SALIDA/$ALPINE_ARCH/linux-lazaro-$pkgver-r$pkgrel.apk" 'boot/config-*' > "$CONFIG_FINAL" 2>/dev/null || true
[ -s "$CONFIG_FINAL" ] || { echo "AVISO: el paquete no trae /boot/config-lazaro."; rm -f "$CONFIG_FINAL"; CONFIG_FINAL=""; }

# --- Resumen: cuánto se ahorra frente a linux-lts ----------------------------
msg "Comparando con linux-lts de Alpine"
t="$(mktemp -d)"
( cd "$t" && apk fetch -q linux-lts >/dev/null 2>&1 ) || true
medir() { # APK -> "MB_comprimido módulos"
	m=$(tar -tzf "$1" 2>/dev/null | grep -c '\.ko' || true)
	echo "$(( $(stat -c %s "$1") / 1048576 )) MB, $m módulos"
}
lts_apk="$(ls "$t"/linux-lts-*.apk 2>/dev/null | head -n 1)"
{
	echo "VERSION=$pkgver-r$pkgrel"
	echo "ALPINE_BRANCH=$ALPINE_BRANCH"
	echo "FIRMA=$FIRMA"
	echo "linux-lazaro: $(medir "$SALIDA/$ALPINE_ARCH/linux-lazaro-$pkgver-r$pkgrel.apk")"
	[ -z "$lts_apk" ] || echo "linux-lts:    $(medir "$lts_apk")"
	if [ -n "$CONFIG_FINAL" ]; then
		for o in PREEMPT PREEMPT_DYNAMIC DEBUG_INFO_BTF INFINIBAND FUSION MLX5_CORE; do
			printf 'CONFIG_%s: %s\n' "$o" "$(sed -n "s/^CONFIG_$o=//p" "$CONFIG_FINAL")"
		done
	fi
} | tee "$SALIDA/resumen.txt"
rm -rf "$t"
chmod -R a+rX "$SALIDA"
msg "Listo: $SALIDA"
