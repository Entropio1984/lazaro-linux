#!/bin/sh
# Prueba live/usr/sbin/lazaro-repositorio y live/usr/sbin/lazaro-kernel sin
# tocar el equipo: un sistema de mentira (LAZARO_REPO_RAIZ y
# LAZARO_KERNEL_RAIZ), una "Release" en una carpeta (file://) y
# grub-mkconfig, grub-set-default, grub-reboot y apk falsos que anotan lo
# que se les pide. Recorre el repositorio (al instalar, activar,
# sincronizar, sin internet, desactivar) y el kernel (instalar, el
# arranque de prueba bien y mal, una actualización y quitar).
#
#   pruebas/kernel.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-kernel"
REPO_PROG="$DIR/live/usr/sbin/lazaro-repositorio"
TMP="$(mktemp -d)"
[ -d "$TMP" ] || exit 1
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
# apk: "add" instala lo pedido (el kernel crea /boot/vmlinuz-lazaro) si
# el repositorio local está puesto y tiene el paquete; "del" lo quita.
cat > "$TMP/bin/apk" <<FIN
#!/bin/sh
echo "apk \$*" >> "$ANOTA"
L="$R/var/lib/lazaro-repositorio/x86_64"
case "\$1" in
	add) grep -qxF "@lazaro $R/var/lib/lazaro-repositorio" "$R/etc/apk/repositories" || exit 1
		[ -s "\$L/APKINDEX.tar.gz" ] || exit 1
		shift
		for p in "\$@"; do
			p="\${p%@lazaro}"
			ls "\$L/\$p"-[0-9]*.apk >/dev/null 2>&1 || exit 1
			printf 'P:%s\n\n' "\$p" >> "$R/lib/apk/db/installed"
			[ "\$p" != linux-lazaro ] || { mkdir -p "$R/boot"; : > "$R/boot/vmlinuz-lazaro"; }
		done ;;
	del) rm -f "$R/boot/vmlinuz-lazaro"; sed -i '/^P:linux-lazaro/d' "$R/lib/apk/db/installed" ;;
	info) [ "\$2" = -e ] && grep -qx "P:\$3" "$R/lib/apk/db/installed" && exit 0; exit 1 ;;
esac
FIN
chmod +x "$TMP/bin"/*
PATH="$TMP/bin:$PATH"

# --- La "Release" publicada ----------------------------------------------------
PUB="$TMP/release"
mkdir -p "$PUB" "$TMP/indice"
publicar() { # "NOMBRE VERSION"...
	: > "$TMP/indice/APKINDEX"
	for pv in "$@"; do
		pn="${pv% *}"; pver="${pv#* }"
		printf 'C:Q1abc=\nP:%s\nV:%s\n\n' "$pn" "$pver" >> "$TMP/indice/APKINDEX"
		[ -e "$PUB/$pn-$pver.apk" ] || echo "$pn $pver" > "$PUB/$pn-$pver.apk"
	done
	(cd "$TMP/indice" && tar -czf "$PUB/APKINDEX.tar.gz" APKINDEX)
}
publicar "lazaro-herramientas 0.1-r500" "linux-lazaro 6.18.59-r0" "linux-lazaro-dev 6.18.59-r0"

# --- Sistema de mentira ----------------------------------------------------------
mkdir -p "$R/etc/default" "$R/etc/apk" "$R/boot/grub" "$R/usr/share/lazaro" "$R/lib/apk/db"
: > "$R/lib/apk/db/installed"
printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$R/etc/default/grub"
echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/main" > "$R/etc/apk/repositories"
echo x86_64 > "$R/etc/apk/arch"
cp "$DIR/live/usr/share/lazaro/lazaro-kernel.initd" "$R/usr/share/lazaro/"
grub-mkconfig -o "$R/boot/grub/grub.cfg"
L="$R/var/lib/lazaro-repositorio/x86_64"

lr() { env LAZARO_REPO_RAIZ="$R" LAZARO_REPO_URL="file://$PUB" sh "$REPO_PROG" "$@"; }
# lazaro-kernel llama a lazaro-repositorio con el mismo sistema de mentira.
printf '#!/bin/sh\nexec env LAZARO_REPO_RAIZ="%s" LAZARO_REPO_URL="file://%s" sh "%s" "$@"\n' "$R" "$PUB" "$REPO_PROG" > "$TMP/bin/lr"
chmod +x "$TMP/bin/lr"

# --- Repositorio: la clave ----------------------------------------------------------
sed -n "/^LLAVE='/,/'\$/p" "$REPO_PROG" | sed "s/^LLAVE='//; s/'\$//" > "$TMP/llave"
espera "repositorio: la clave de adentro es repo/lazaro.rsa.pub" "$(cat "$TMP/llave")" "$(cat "$DIR/repo/lazaro.rsa.pub")"

# --- Repositorio: al instalar Lázaro (solo prepara) ---------------------------------
I="$TMP/instalando"
mkdir -p "$I/etc/apk"
echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/main" > "$I/etc/apk/repositories"
espera "al instalar: prepara" "$(sh "$REPO_PROG" --activar --raiz "$I" 2>&1)" LAZARO-REPOSITORIO-PREPARADO
espera "al instalar: clave puesta" "$(cat "$I/etc/apk/keys/lazaro.rsa.pub")" "$(cat "$DIR/repo/lazaro.rsa.pub")"
[ -x "$I/usr/local/sbin/lazaro-repositorio" ] && ok "al instalar: programa en /usr/local/sbin" || mal "al instalar: falta el programa"
[ -x "$I/etc/init.d/lazaro-repositorio" ] && [ -L "$I/etc/runlevels/default/lazaro-repositorio" ] &&
	ok "al instalar: servicio en el arranque" || mal "al instalar: falta el servicio"
contiene "al instalar: tarea diaria" "lazaro-repositorio --arranque" "$I/etc/periodic/daily/lazaro-repositorio"
espera "al instalar: sin @lazaro hasta tener índice" "$(grep -c '@lazaro' "$I/etc/apk/repositories")" 0

# --- Repositorio: activar en un equipo ya instalado ---------------------------------
: > "$ANOTA"
salida="$(lr --activar 2>&1)" || mal "activar terminó con error: $salida"
case "$salida" in *LAZARO-REPOSITORIO-ACTIVO*) ok "activar: responde activo" ;; *) mal "activar: $salida" ;; esac
contiene "activar: instala lazaro-herramientas" "apk add lazaro-herramientas@lazaro" "$ANOTA"
contiene "activar: repositorio @lazaro" "@lazaro $R/var/lib/lazaro-repositorio" "$R/etc/apk/repositories"
[ -s "$L/lazaro-herramientas-0.1-r500.apk" ] && ok "activar: bajó las herramientas" || mal "activar: no bajó las herramientas"
[ ! -e "$L/linux-lazaro-6.18.59-r0.apk" ] && ok "activar: sin el kernel (no está instalado)" || mal "activar: bajó el kernel sin pedirlo"
lr --activar >/dev/null 2>&1 || true
espera "activar dos veces: un solo repositorio" "$(grep -c '^@lazaro' "$R/etc/apk/repositories")" 1

# --- Repositorio: versión nueva y sin internet --------------------------------------
publicar "lazaro-herramientas 0.1-r501" "linux-lazaro 6.18.59-r0" "linux-lazaro-dev 6.18.59-r0"
lr --sincronizar
[ -s "$L/lazaro-herramientas-0.1-r501.apk" ] && ok "sincronizar: baja la versión nueva" || mal "sincronizar: no bajó la nueva"
[ ! -e "$L/lazaro-herramientas-0.1-r500.apk" ] && ok "sincronizar: borra la vieja" || mal "sincronizar: dejó la vieja"
if env LAZARO_REPO_RAIZ="$R" LAZARO_REPO_URL="file://$TMP/no-existe" sh "$REPO_PROG" --sincronizar 2>/dev/null; then
	mal "sin internet: no avisó del error"
else
	ok "sin internet: avisa del error"
fi
[ -s "$L/APKINDEX.tar.gz" ] && [ -s "$L/lazaro-herramientas-0.1-r501.apk" ] &&
	ok "sin internet: el repositorio anterior sigue" || mal "sin internet: perdió el repositorio"

lk() { # UNAME ARGS...
	u="$1"; shift
	env LAZARO_KERNEL_RAIZ="$R" LAZARO_KERNEL_UNAME="$u" LAZARO_REPO_PROG="$TMP/bin/lr" sh "$PROG" "$@"
}
LTS="gnulinux-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab>gnulinux-lts-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab"
LAZ="gnulinux-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab>gnulinux-lazaro-advanced-0f1e2d3c-aaaa-bbbb-cccc-1234567890ab"

# --- Instalar ---------------------------------------------------------------------
: > "$ANOTA"
salida="$(lk 6.18.59-0-lts --instalar 2>&1)" || mal "instalar terminó con error: $salida"
case "$salida" in *LAZARO-KERNEL-INSTALADO*) ok "instalar: responde instalado" ;; *) mal "instalar: $salida" ;; esac
[ -s "$L/linux-lazaro-6.18.59-r0.apk" ] && ok "instalar: descargó el paquete" || mal "instalar: no descargó el paquete"
[ ! -e "$L/linux-lazaro-dev-6.18.59-r0.apk" ] && ok "instalar: sin cabeceras (no hay akms)" || mal "instalar: bajó las cabeceras sin akms"
contiene "instalar: GRUB_DEFAULT=saved" "GRUB_DEFAULT=saved" "$R/etc/default/grub"
contiene "instalar: apk add linux-lazaro@lazaro" "apk add linux-lazaro@lazaro" "$ANOTA"
contiene "instalar: el de Alpine sigue por defecto" "grub-set-default $LTS" "$ANOTA"
contiene "instalar: el Lázaro arranca una vez de prueba" "grub-reboot $LAZ" "$ANOTA"
espera "instalar: estado prueba" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" prueba
[ -L "$R/etc/runlevels/default/lazaro-kernel" ] && ok "instalar: servicio en el arranque" || mal "instalar: falta el servicio"
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

# --- Kernel nuevo publicado: la tarea diaria lo trae (está instalado) -------------
publicar "lazaro-herramientas 0.1-r501" "linux-lazaro 6.18.60-r0" "linux-lazaro-dev 6.18.60-r0"
lr --sincronizar
[ -s "$L/linux-lazaro-6.18.60-r0.apk" ] && ok "kernel nuevo: la tarea diaria lo baja" || mal "kernel nuevo: no lo bajó"
[ ! -e "$L/linux-lazaro-6.18.59-r0.apk" ] && ok "kernel nuevo: borra el viejo" || mal "kernel nuevo: dejó el viejo"

# --- Quitar ---------------------------------------------------------------------
: > "$ANOTA"
salida="$(lk 6.18.60-0-lazaro --quitar 2>&1)" || mal "quitar terminó con error: $salida"
contiene "quitar: el de Alpine por defecto" "grub-set-default $LTS" "$ANOTA"
contiene "quitar: desinstala" "apk del linux-lazaro linux-lazaro-dev" "$ANOTA"
espera "quitar: GRUB como estaba" "$(cat "$R/etc/default/grub")" "$(printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"')"
contiene "quitar: el repositorio sigue (herramientas)" "@lazaro" "$R/etc/apk/repositories"
[ ! -e "$R/etc/runlevels/default/lazaro-kernel" ] && [ ! -e "$R/etc/apk/commit_hooks.d/lazaro-kernel.hook" ] \
	&& ok "quitar: sin servicio ni gancho" || mal "quitar: quedó el servicio o el gancho"
espera "quitar: estado no" "$(sed -n 's/^ESTADO=//p' "$R/etc/lazaro/kernel.conf")" no
lr --sincronizar
[ ! -e "$L/linux-lazaro-6.18.60-r0.apk" ] && [ -s "$L/lazaro-herramientas-0.1-r501.apk" ] &&
	ok "quitar: la tarea diaria ya no baja el kernel" || mal "quitar: el kernel sigue en el repositorio local"
grep -q lazaro "$R/boot/grub/grub.cfg" && mal "quitar: el menú sigue con el Lázaro" || ok "quitar: el menú solo tiene el de Alpine"

# --- Repositorio: desactivar --------------------------------------------------------
espera "desactivar: responde" "$(lr --desactivar)" LAZARO-REPOSITORIO-DESACTIVADO
espera "desactivar: repositorios como estaban" "$(cat "$R/etc/apk/repositories")" "https://dl-cdn.alpinelinux.org/alpine/v3.24/main"
[ ! -e "$R/etc/runlevels/default/lazaro-repositorio" ] && [ ! -e "$R/etc/periodic/daily/lazaro-repositorio" ] &&
	ok "desactivar: sin servicio ni tarea diaria" || mal "desactivar: quedó el servicio o la tarea"

echo
if [ "$fallos" -eq 0 ]; then
	echo "Repositorio y kernel Lázaro: $n comprobaciones bien."
else
	echo "Repositorio y kernel Lázaro: $fallos de $n comprobaciones fallaron." >&2
	exit 1
fi
