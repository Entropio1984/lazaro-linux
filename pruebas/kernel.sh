#!/bin/sh
# Prueba live/usr/sbin/lazaro-kernel sin tocar el equipo: un sistema de
# mentira (LAZARO_KERNEL_RAIZ), una "Release" en una carpeta (file://) y
# grub-mkconfig, grub-set-default, grub-reboot y apk falsos que anotan lo
# que se les pide. Recorre instalar, el arranque de prueba bien y mal, una
# actualización y quitar.
#
#   pruebas/kernel.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-kernel"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/raiz"
ANOTA="$TMP/ordenes"

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }
espera() { if [ "$2" = "$3" ]; then ok "$1"; else mal "$1: se esperaba '$3' y salió '$2'"; fi; }
contiene() { if grep -qF -- "$2" "$3" 2>/dev/null; then ok "$1"; else mal "$1: falta '$2' en ${3##*/}"; fi; }

# --- Programas falsos -------------------------------------------------------
mkdir -p "$TMP/bin"
for p in grub-set-default grub-reboot; do
	printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$p" "$ANOTA" > "$TMP/bin/$p"
done
# grub-mkconfig: un grub.cfg con la forma del de Alpine (10_linux), con el
# kernel Lázaro solo si está "instalado".
cat > "$TMP/bin/grub-mkconfig" <<EOF
#!/bin/sh
echo "grub-mkconfig" >> "$ANOTA"
u=0f1e2d3c-aaaa-bbbb-cccc-1234567890ab
{
echo "menuentry 'Alpine Linux' --class alpine \\\$menuentry_id_option 'gnulinux-simple-\$u' {"
echo "	linux /boot/vmlinuz-lts root=UUID=\$u"
echo "}"
echo "submenu 'Advanced options for Alpine Linux' \\\$menuentry_id_option 'gnulinux-advanced-\$u' {"
echo "	menuentry 'Alpine Linux, with Linux lts' --class alpine \\\$menuentry_id_option 'gnulinux-lts-advanced-\$u' {"
echo "		linux /boot/vmlinuz-lts root=UUID=\$u"
echo "	}"
echo "	menuentry 'Alpine Linux, with Linux lts (recovery mode)' \\\$menuentry_id_option 'gnulinux-lts-recovery-\$u' {"
echo "	}"
if [ -e "$R/boot/vmlinuz-lazaro" ]; then
echo "	menuentry 'Alpine Linux, with Linux lazaro' --class alpine \\\$menuentry_id_option 'gnulinux-lazaro-advanced-\$u' {"
echo "		linux /boot/vmlinuz-lazaro root=UUID=\$u"
echo "	}"
fi
echo "}"
} > "\$2"
EOF
# apk: "add" instala el kernel (crea /boot/vmlinuz-lazaro), "del" lo quita.
cat > "$TMP/bin/apk" <<EOF
#!/bin/sh
echo "apk \$*" >> "$ANOTA"
case "\$1" in
	add) grep -qxF "@lazaro $R/var/lib/lazaro-kernel" "$R/etc/apk/repositories" || exit 1
		[ -s "$R/var/lib/lazaro-kernel/x86_64/APKINDEX.tar.gz" ] || exit 1
		mkdir -p "$R/boot"; : > "$R/boot/vmlinuz-lazaro" ;;
	del) rm -f "$R/boot/vmlinuz-lazaro" ;;
	info) [ "\$2" = -e ] && [ "\$3" = linux-lazaro ] && [ -e "$R/boot/vmlinuz-lazaro" ] && exit 0; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin"/*
PATH="$TMP/bin:$PATH"

# --- La "Release" publicada ----------------------------------------------------
PUB="$TMP/release"
mkdir -p "$PUB" "$TMP/indice"
printf 'C:Q1abc=\nP:linux-lazaro\nV:6.18.59-r0\n\nC:Q1def=\nP:linux-lazaro-dev\nV:6.18.59-r0\n\n' > "$TMP/indice/APKINDEX"
(cd "$TMP/indice" && tar -czf "$PUB/APKINDEX.tar.gz" APKINDEX)
echo kernel > "$PUB/linux-lazaro-6.18.59-r0.apk"
echo cabeceras > "$PUB/linux-lazaro-dev-6.18.59-r0.apk"

# --- Sistema de mentira ----------------------------------------------------------
mkdir -p "$R/etc/default" "$R/etc/apk" "$R/boot/grub" "$R/usr/share/lazaro"
printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$R/etc/default/grub"
echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/main" > "$R/etc/apk/repositories"
echo x86_64 > "$R/etc/apk/arch"
echo "clave publica" > "$R/usr/share/lazaro/lazaro-kernel.rsa.pub"
cp "$DIR/live/usr/share/lazaro/lazaro-kernel.initd" "$R/usr/share/lazaro/"
grub-mkconfig -o "$R/boot/grub/grub.cfg"

lk() { # UNAME ARGS...
	u="$1"; shift
	env LAZARO_KERNEL_RAIZ="$R" LAZARO_KERNEL_URL="file://$PUB" LAZARO_KERNEL_UNAME="$u" sh "$PROG" "$@"
}
LTS="gnulinux-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab>gnulinux-lts-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab"
LAZ="gnulinux-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab>gnulinux-lazaro-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab"

# --- Instalar ---------------------------------------------------------------------
: > "$ANOTA"
salida="$(lk 6.18.59-0-lts --instalar 2>&1)" || mal "instalar terminó con error: $salida"
case "$salida" in *LAZARO-KERNEL-INSTALADO*) ok "instalar: responde instalado" ;; *) mal "instalar: $salida" ;; esac
[ -s "$R/var/lib/lazaro-kernel/x86_64/linux-lazaro-6.18.59-r0.apk" ] && ok "instalar: descargó el paquete" || mal "instalar: no descargó el paquete"
[ -s "$R/etc/apk/keys/lazaro-kernel.rsa.pub" ] && ok "instalar: clave en /etc/apk/keys" || mal "instalar: falta la clave"
contiene "instalar: repositorio @lazaro" "@lazaro $R/var/lib/lazaro-kernel" "$R/etc/apk/repositories"
contiene "instalar: GRUB_DEFAULT=saved" "GRUB_DEFAULT=saved" "$R/etc/default/grub"
contiene "instalar: apk add linux-lazaro@lazaro" "apk add linux-lazaro@lazaro" "$ANOTA"
contiene "instalar: el de Alpine sigue por defecto" "grub-set-default $LTS" "$ANOTA"
contiene "instalar: el Lázaro arranca una vez de prueba" "grub-reboot $LAZ" "$ANOTA"
espera "instalar: estado prueba" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" prueba
[ -L "$R/etc/runlevels/default/lazaro-kernel" ] && ok "instalar: servicio en el arranque" || mal "instalar: falta el servicio"
[ -x "$R/etc/periodic/daily/lazaro-kernel" ] && ok "instalar: tarea diaria" || mal "instalar: falta la tarea diaria"
[ -x "$R/etc/apk/commit_hooks.d/lazaro-kernel.hook" ] && ok "instalar: gancho de apk" || mal "instalar: falta el gancho de apk"
# Instalar dos veces no duplica el repositorio ni el bloque.
lk 6.18.59-0-lts --instalar >/dev/null 2>&1 || true
espera "instalar dos veces: un solo repositorio" "$(grep -c '^@lazaro' "$R/etc/apk/repositories")" 1
espera "instalar dos veces: un solo bloque" "$(grep -c 'lazaro-kernel: inicio' "$R/etc/default/grub")" 1

# --- Arranque de prueba que falla: arrancó el de Alpine ---------------------------
: > "$ANOTA"
espera "prueba fallida: aviso" "$(lk 6.18.59-0-lts --arranque)" LAZARO-KERNEL-FALLO
espera "prueba fallida: estado fallo" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" fallo
[ -s "$ANOTA" ] && mal "prueba fallida: tocó GRUB ($(cat "$ANOTA"))" || ok "prueba fallida: GRUB sigue con el de Alpine"

# --- Arranque de prueba bien -----------------------------------------------------
lk 6.18.59-0-lts --instalar >/dev/null 2>&1
: > "$ANOTA"
espera "prueba bien: confirmado" "$(lk 6.18.59-0-lazaro --arranque)" LAZARO-KERNEL-CONFIRMADO
contiene "prueba bien: el Lázaro queda por defecto" "grub-set-default $LAZ" "$ANOTA"
espera "prueba bien: estado activo" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" activo
espera "ya confirmado: el servicio no hace nada" "$(lk 6.18.59-0-lazaro --arranque)" ""

# --- Actualización: el gancho de apk vuelve a probar ---------------------------
: > "$ANOTA"
espera "sin cambios: el gancho no hace nada" "$(lk 6.18.59-0-lazaro --nueva-version)" ""
touch -d '+1 minute' "$R/boot/vmlinuz-lazaro" 2>/dev/null || { sleep 1; touch "$R/boot/vmlinuz-lazaro"; }
espera "kernel nuevo: vuelve a prueba" "$(lk 6.18.59-0-lazaro --nueva-version)" LAZARO-KERNEL-PRUEBA-NUEVA
contiene "kernel nuevo: el de Alpine por defecto" "grub-set-default $LTS" "$ANOTA"
contiene "kernel nuevo: el Lázaro de prueba" "grub-reboot $LAZ" "$ANOTA"

# --- Sincronizar: versión nueva publicada ----------------------------------------
printf 'C:Q1xyz=\nP:linux-lazaro\nV:6.18.60-r0\n\n' > "$TMP/indice/APKINDEX"
(cd "$TMP/indice" && tar -czf "$PUB/APKINDEX.tar.gz" APKINDEX)
echo kernel2 > "$PUB/linux-lazaro-6.18.60-r0.apk"
lk 6.18.59-0-lazaro --sincronizar
[ -s "$R/var/lib/lazaro-kernel/x86_64/linux-lazaro-6.18.60-r0.apk" ] && ok "sincronizar: baja la versión nueva" || mal "sincronizar: no bajó la nueva"
[ ! -e "$R/var/lib/lazaro-kernel/x86_64/linux-lazaro-6.18.59-r0.apk" ] && ok "sincronizar: borra la vieja" || mal "sincronizar: dejó la vieja"
# Sin internet: no rompe lo que ya había.
if env LAZARO_KERNEL_RAIZ="$R" LAZARO_KERNEL_URL="file://$TMP/no-existe" sh "$PROG" --sincronizar 2>/dev/null; then
	mal "sin internet: no avisó del error"
else
	ok "sin internet: avisa del error"
fi
[ -s "$R/var/lib/lazaro-kernel/x86_64/APKINDEX.tar.gz" ] && ok "sin internet: el índice anterior sigue" || mal "sin internet: perdió el índice"

# --- Quitar ---------------------------------------------------------------------
: > "$ANOTA"
salida="$(lk 6.18.60-0-lazaro --quitar 2>&1)" || mal "quitar terminó con error: $salida"
contiene "quitar: el de Alpine por defecto" "grub-set-default $LTS" "$ANOTA"
contiene "quitar: desinstala" "apk del linux-lazaro linux-lazaro-dev" "$ANOTA"
espera "quitar: GRUB como estaba" "$(cat "$R/etc/default/grub")" "$(printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"')"
espera "quitar: repositorios como estaban" "$(cat "$R/etc/apk/repositories")" "https://dl-cdn.alpinelinux.org/alpine/v3.24/main"
[ ! -e "$R/etc/runlevels/default/lazaro-kernel" ] && [ ! -e "$R/etc/apk/commit_hooks.d/lazaro-kernel.hook" ] \
	&& ok "quitar: sin servicio ni gancho" || mal "quitar: quedó el servicio o el gancho"
espera "quitar: estado no" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" no
grep -q lazaro "$R/boot/grub/grub.cfg" && mal "quitar: el menú sigue con el Lázaro" || ok "quitar: el menú solo tiene el de Alpine"

echo
if [ "$fallos" -eq 0 ]; then
	echo "Kernel Lázaro: $n comprobaciones bien."
else
	echo "Kernel Lázaro: $fallos de $n comprobaciones fallaron." >&2
	exit 1
fi
