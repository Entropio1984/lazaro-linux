#!/bin/sh
# Arranca en QEMU el kernel Lázaro recién compilado y, para comparar, el
# linux-lts de Alpine, con un sistema mínimo en memoria (busybox). Revisa
# que el kernel Lázaro llegue a ejecutar programas con la expropiación
# completa ("Dynamic Preempt: full") y muestra cuánta memoria le queda
# libre a cada uno al arrancar.
#
#   pruebas/kernel-arranque.sh salida/kernel/x86_64/linux-lazaro-*.apk [linux-lts.apk]
#
# Necesita qemu-system-x86_64 y cpio. Sin el segundo argumento solo prueba
# el kernel Lázaro.

set -eu

[ $# -ge 1 ] && [ -f "$1" ] || { echo "Uso: $0 linux-lazaro.apk [linux-lts.apk]" >&2; exit 2; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# busybox estático de Alpine para el sistema mínimo.
# shellcheck disable=SC2034
LAZARO_DIR="$DIR" # lo usa lib.sh
# shellcheck disable=SC1091
. "$DIR/lib.sh"
mkdir -p "$TMP/raiz/bin"
curl -fsSL --retry 3 -o "$TMP/indice.tar.gz" "$ALPINE_REPO_MAIN/$ALPINE_ARCH/APKINDEX.tar.gz"
bb_ver="$(tar -xzOf "$TMP/indice.tar.gz" APKINDEX | awk '/^P:busybox-static$/ { p = 1 } p && /^V:/ { print substr($0, 3); exit }')"
[ -n "$bb_ver" ] || { echo "No se encontró busybox-static en el índice de Alpine." >&2; exit 1; }
curl -fsSL --retry 3 -o "$TMP/bb.apk" "$ALPINE_REPO_MAIN/$ALPINE_ARCH/busybox-static-$bb_ver.apk"
# Un .apk son varios tar.gz seguidos: tar puede quejarse del final aunque
# haya sacado el archivo, así que se revisa el resultado y no su salida.
tar -xzf "$TMP/bb.apk" -C "$TMP" bin/busybox.static 2>/dev/null || true
[ -s "$TMP/bin/busybox.static" ] || { echo "No se pudo sacar busybox.static del paquete." >&2; exit 1; }
mv "$TMP/bin/busybox.static" "$TMP/raiz/bin/busybox"
chmod 755 "$TMP/raiz/bin/busybox"
cat > "$TMP/raiz/init" <<'EOF'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo "LAZARO-KERNEL-ARRANCO $(uname -r)"
echo "LAZARO-KERNEL-PREEMPT $(dmesg | grep -o 'Dynamic Preempt: [a-z]*' | tail -n 1)"
echo "LAZARO-KERNEL-MEMORIA $(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { printf "total=%d libre=%d", t / 1024, a / 1024 }' /proc/meminfo)"
poweroff -f
EOF
chmod 755 "$TMP/raiz/init"
(cd "$TMP/raiz" && find . | cpio -o -H newc --quiet | gzip -9) > "$TMP/initramfs.gz"

acel=""
[ -w /dev/kvm ] && acel="-enable-kvm -cpu host"

arrancar() { # APK NOMBRE -> salida en $TMP/NOMBRE.log
	mkdir -p "$TMP/$2"
	tar -xzf "$1" -C "$TMP/$2" boot 2>/dev/null || true
	k="$(ls "$TMP/$2"/boot/vmlinuz-* 2>/dev/null | head -n 1)"
	[ -n "$k" ] || { echo "No se encontró boot/vmlinuz-* en $1." >&2; exit 1; }
	# shellcheck disable=SC2086
	timeout 300 qemu-system-x86_64 $acel -m 1024 -nographic -no-reboot \
		-kernel "$k" -initrd "$TMP/initramfs.gz" \
		-append "console=ttyS0 panic=-1 quiet loglevel=3" > "$TMP/$2.log" 2>&1 || true
	tr -d '\r' < "$TMP/$2.log" | grep '^LAZARO-KERNEL-' | sed "s/^/[$2] /"
}

arrancar "$1" lazaro
if ! grep -q '^LAZARO-KERNEL-ARRANCO .*-lazaro' "$TMP/lazaro.log"; then
	echo "FALLO: el kernel Lázaro no llegó a ejecutar programas. Últimas líneas:" >&2
	tr -d '\r' < "$TMP/lazaro.log" | tail -n 40 >&2
	exit 1
fi
if ! grep -q 'LAZARO-KERNEL-PREEMPT Dynamic Preempt: full' "$TMP/lazaro.log"; then
	echo "FALLO: el kernel Lázaro no arrancó con la expropiación completa." >&2
	exit 1
fi
echo "OK: el kernel Lázaro arranca con la expropiación completa."

if [ -n "${2:-}" ] && [ -f "$2" ]; then
	arrancar "$2" lts
	l="$(sed -n 's/.*LAZARO-KERNEL-MEMORIA total=\([0-9]*\) libre=\([0-9]*\).*/\1 \2/p' "$TMP/lazaro.log" | tr -d '\r')"
	a="$(sed -n 's/.*LAZARO-KERNEL-MEMORIA total=\([0-9]*\) libre=\([0-9]*\).*/\1 \2/p' "$TMP/lts.log" | tr -d '\r')"
	if [ -n "$l" ] && [ -n "$a" ]; then
		set -- $l $a
		echo "Memoria libre al arrancar con 1024 MB: Lázaro $2 MB, Alpine lts $4 MB (diferencia $(( $2 - $4 )) MB)."
	fi
fi
