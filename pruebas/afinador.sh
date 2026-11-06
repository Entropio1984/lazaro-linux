#!/bin/sh
# Prueba live/usr/sbin/lazaro-afinador sin tocar el equipo: arma un /sys y
# un /proc falsos (equipos viejos y nuevos) y un sistema instalado de
# mentira (--raiz) con su /etc/default/grub, y revisa qué ajustes elige,
# que aplicar y deshacer dejen los archivos como corresponde y que el
# perfil separe el hardware fijo del extraíble.
#
#   pruebas/afinador.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-afinador"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }

cat > "$TMP/modules.alias" <<'EOS'
alias pci:v00008086d00000116sv*sd*bc03sc*i* i915
alias pci:v000010DEd*sv*sd*bc03sc*i* nouveau
alias pci:v00008086d00001C22sv*sd*bc*sc*i* i2c_i801
alias pci:v000010ECd00008168sv*sd*bc*sc*i* r8169
alias usb:v0BDAp57B4d*dc*dsc*dp*ic0Eisc01ip00in* uvcvideo
alias usb:v*p*d*dc*dsc*dp*ic08isc06ip50in* usb_storage
alias usb:v046Dp*d*dc*dsc*dp*ic03isc*ip*in* usbhid
EOS

# equipo NOMBRE RAM_KB DRIVER GOBERNADOR FLAGS DISCO(HDD|SSD)
equipo() {
	R="$TMP/$1"
	S="$R/sys"; P="$R/proc"; D="$R/destino"
	mkdir -p "$S/devices/system/cpu/cpu0/cpufreq" "$S/devices/system/cpu/cpufreq/policy0" \
		"$S/kernel/mm/lru_gen" "$S/kernel/mm/transparent_hugepage" "$P" \
		"$D/etc/default" "$D/etc/init.d" "$D/boot" "$S/class/dmi/id"
	printf 'MemTotal:       %s kB\n' "$2" > "$P/meminfo"
	printf 'processor\t: 0\nmodel name\t: Procesador de prueba\nflags\t\t: %s\n' "$5" > "$P/cpuinfo"
	echo "BOOT_IMAGE=/boot/vmlinuz-lts root=/dev/sda2 quiet" > "$P/cmdline"
	printf 'Filename\tType\tSize\tUsed\tPriority\n' > "$P/swaps"
	echo "/dev/sda2 / ext4 rw 0 0" > "$P/mounts"
	[ -z "$3" ] || {
		echo "$3" > "$S/devices/system/cpu/cpu0/cpufreq/scaling_driver"
		echo "$4" > "$S/devices/system/cpu/cpu0/cpufreq/scaling_governor"
		echo "$4" > "$S/devices/system/cpu/cpufreq/policy0/scaling_governor"
		echo "ondemand performance schedutil" > "$S/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
	}
	echo 0x0007 > "$S/kernel/mm/lru_gen/enabled"
	echo 0 > "$S/kernel/mm/lru_gen/min_ttl_ms"
	echo "[always] madvise never" > "$S/kernel/mm/transparent_hugepage/enabled"
	echo "always defer defer+madvise [madvise] never" > "$S/kernel/mm/transparent_hugepage/defrag"
	# Disco y piezas: gráfica Intel y red Realtek (fijas), webcam interna
	# (USB "fixed") y un pendrive (USB "removable").
	mkdir -p "$S/block/sda/queue"
	[ "$6" = HDD ] && echo 1 > "$S/block/sda/queue/rotational" || echo 0 > "$S/block/sda/queue/rotational"
	echo 976773168 > "$S/block/sda/size"
	echo "mq-deadline [bfq] none" > "$S/block/sda/queue/scheduler"
	mkdir -p "$S/bus/pci/devices/0000:00:02.0" "$S/bus/pci/devices/0000:03:00.0"
	echo "pci:v00008086d00000116sv00001043sd00001B6Dbc03sc00i00" > "$S/bus/pci/devices/0000:00:02.0/modalias"
	echo "pci:v000010ECd00008168sv00001043sd000016D5bc02sc00i00" > "$S/bus/pci/devices/0000:03:00.0/modalias"
	mkdir -p "$S/devices/usb1/1-1/1-1:1.0" "$S/devices/usb1/1-2/1-2:1.0" "$S/bus/usb/devices"
	echo fixed > "$S/devices/usb1/1-1/removable"
	echo removable > "$S/devices/usb1/1-2/removable"
	echo "usb:v0BDAp57B4d0012dcEFdsc02dp01ic0Eisc01ip00in00" > "$S/devices/usb1/1-1/1-1:1.0/modalias"
	echo "usb:v0781p5567d0100dc00dsc00dp00ic08isc06ip50in00" > "$S/devices/usb1/1-2/1-2:1.0/modalias"
	ln -s ../../../devices/usb1/1-1/1-1:1.0 "$S/bus/usb/devices/1-1:1.0"
	ln -s ../../../devices/usb1/1-2/1-2:1.0 "$S/bus/usb/devices/1-2:1.0"
	printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 splash"\n' > "$D/etc/default/grub"
	cp "$DIR/live/usr/share/lazaro/lazaro-afinador.initd" "$D/etc/init.d/lazaro-afinador"
	printf 'CONFIG_PREEMPT_VOLUNTARY=y\nCONFIG_PREEMPT_DYNAMIC=y\nCONFIG_LRU_GEN=y\n' > "$D/boot/config-lts"
}

af() { # EQUIPO ARGS...
	R="$TMP/$1"; shift
	env LAZARO_SYS="$R/sys" LAZARO_PROC="$R/proc" LAZARO_MODULOS="$TMP/modules.alias" \
		LAZARO_AFINADOR_LOG="/var/log/lazaro-afinador.log" LAZARO_PRUEBA=1 \
		sh "$PROG" "$@"
}
estado() { # EQUIPO CLAVE -> estado
	af "$1" --revisar --raiz "$TMP/$1/destino" | awk -F'\t' -v c="$2" '$2 == c { print $1 }'
}
espera() { # DESCRIPCIÓN OBTENIDO ESPERADO
	if [ "$2" = "$3" ]; then ok "$1"; else mal "$1: se esperaba '$3' y salió '$2'"; fi
}

# --- Portátil viejo: 2 GB, Sempron con acpi-cpufreq en ondemand, disco HDD.
equipo viejo 2000000 acpi-cpufreq ondemand "fpu sse sse2 lahf_lm" HDD
espera "viejo: nivel x86-64 v1" "$(af viejo --perfil | sed -n 's/^Nivel x86-64: //p')" v1
espera "viejo: preempt pendiente" "$(estado viejo preempt)" pendiente
espera "viejo: páginas gigantes pendiente (2 GB)" "$(estado viejo paginas)" pendiente
espera "viejo: cpu pendiente (acpi-cpufreq en ondemand)" "$(estado viejo cpu)" pendiente
espera "viejo: mitigaciones solo informa" "$(estado viejo mitigaciones)" info
D="$TMP/viejo/destino"
salida="$(af viejo --aplicar --raiz "$D")"
case "$salida" in "LAZARO-AFINADOR-OK preempt=full") ok "viejo: aplicar responde OK con preempt=full" ;;
	*) mal "viejo: salida de --aplicar: $salida" ;; esac
grep -q 'vm.dirty_bytes = 50331648' "$D/etc/sysctl.d/60-lazaro-afinador.conf" \
	&& ok "viejo: tope de escritura en sysctl.d" || mal "viejo: falta sysctl.d"
grep -q '^GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT preempt=full"$' "$D/etc/default/grub" \
	&& ok "viejo: preempt=full en /etc/default/grub" || mal "viejo: falta el bloque de GRUB"
# El bloque debe dar la línea completa al leerse como shell.
linea="$(sh -c ". '$D/etc/default/grub'; echo \"\$GRUB_CMDLINE_LINUX_DEFAULT\"")"
espera "viejo: GRUB conserva lo anterior" "$linea" "modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 splash preempt=full"
[ -L "$D/etc/runlevels/default/lazaro-afinador" ] && ok "viejo: servicio en el arranque" || mal "viejo: falta el servicio"
espera "viejo: escritura aplicada" "$(estado viejo escritura)" aplicado
# Aplicar dos veces no duplica el bloque.
af viejo --aplicar --raiz "$D" >/dev/null
espera "viejo: un solo bloque tras aplicar dos veces" "$(grep -c 'lazaro-afinador: inicio' "$D/etc/default/grub")" 1
# Mitigaciones: opcionales, se suman al bloque.
af viejo --mitigaciones si --raiz "$D" 2>/dev/null
grep -q 'preempt=full mitigations=off' "$D/etc/default/grub" && ok "viejo: mitigations=off a pedido" || mal "viejo: mitigations=off no quedó"
espera "viejo: mitigaciones aplicadas" "$(estado viejo mitigaciones)" aplicado
# Deshacer deja GRUB como estaba.
af viejo --deshacer --raiz "$D" >/dev/null
espera "viejo: deshacer limpia GRUB" "$(cat "$D/etc/default/grub")" "$(printf 'GRUB_TIMEOUT=2\nGRUB_CMDLINE_LINUX_DEFAULT="modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 splash"')"
[ ! -e "$D/etc/sysctl.d/60-lazaro-afinador.conf" ] && ok "viejo: deshacer quita sysctl.d" || mal "viejo: sysctl.d sigue"
[ ! -e "$D/etc/runlevels/default/lazaro-afinador" ] && ok "viejo: deshacer quita el servicio" || mal "viejo: el servicio sigue"
# Un bloque sin la marca de cierre (editado a mano) no se toca: se
# perderían las líneas de abajo.
cp "$D/etc/default/grub" "$TMP/grub.bien"
printf '# lazaro-afinador: inicio (no editar entre estas marcas)\nGRUB_TIMEOUT=5\n' >> "$D/etc/default/grub"
cp "$D/etc/default/grub" "$TMP/grub.roto"
if af viejo --aplicar --raiz "$D" >/dev/null 2>&1; then mal "viejo: aplicó con un bloque roto"; else ok "viejo: bloque sin cierre, no aplica"; fi
cmp -s "$D/etc/default/grub" "$TMP/grub.roto" && ok "viejo: bloque sin cierre, GRUB intacto" || mal "viejo: tocó GRUB con un bloque roto"
cp "$TMP/grub.bien" "$D/etc/default/grub"
# Servicio de arranque: aplica en /sys (falso) con el afinador activo.
af viejo --aplicar --raiz "$D" >/dev/null
cp "$D/etc/lazaro/afinador.conf" "$TMP/afinador.conf"
R="$TMP/viejo"
# --arranque lee la configuración del sistema en marcha: LAZARO_CONF
# apunta a la que dejó --aplicar.
env LAZARO_SYS="$R/sys" LAZARO_PROC="$R/proc" LAZARO_PRUEBA=1 LAZARO_AFINADOR_LOG="$TMP/log" \
	LAZARO_KCONFIG="$D/boot/config-lts" LAZARO_CONF="$TMP/afinador.conf" sh "$PROG" --arranque
espera "arranque: protección de memoria" "$(cat "$R/sys/kernel/mm/lru_gen/min_ttl_ms")" 1000
espera "arranque: páginas gigantes madvise" "$(cat "$R/sys/kernel/mm/transparent_hugepage/enabled")" madvise
espera "arranque: cpu en schedutil" "$(cat "$R/sys/devices/system/cpu/cpufreq/policy0/scaling_governor")" schedutil

# Perfil: hardware fijo y extraíble por separado.
perf="$(af viejo --perfil)"
fijo="$(printf '%s\n' "$perf" | sed -n '/^== Controladores del hardware fijo/{n;p;}')"
extr="$(printf '%s\n' "$perf" | sed -n '/^== Controladores de lo conectado por USB/{n;p;}')"
falta=""
for m in i915 r8169 uvcvideo; do case " $fijo " in *" $m "*) ;; *) falta="$falta $m" ;; esac; done
[ -z "$falta" ] && ok "perfil: fijo tiene gráfica, red y webcam interna" || mal "perfil: al fijo le falta$falta ($fijo)"
case " $fijo " in *" usb_storage "*|*" nouveau "*) mal "perfil: fijo tiene de más: $fijo" ;; *) ok "perfil: fijo sin pendrive ni nouveau" ;; esac
case " $extr " in *" usb_storage "*) ok "perfil: el pendrive es extraíble" ;; *) mal "perfil: extraíble = $extr" ;; esac
espera "--modulos = fijo" "$(af viejo --modulos | tr '\n' ' ' | sed 's/ $//')" "${fijo% }"

# --- Equipo nuevo: 16 GB, Ryzen con amd-pstate, SSD.
equipo nuevo 16000000 amd-pstate-epp powersave "cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 avx avx2 bmi1 bmi2 f16c fma abm movbe xsave" SSD
espera "nuevo: nivel x86-64 v3" "$(af nuevo --perfil | sed -n 's/^Nivel x86-64: //p')" v3
espera "nuevo: páginas gigantes no hace falta (16 GB)" "$(estado nuevo paginas)" no-aplica
espera "nuevo: cpu no se toca (amd-pstate)" "$(estado nuevo cpu)" no-aplica

# --- Sin escritorio y kernel sin modo dinámico: sin preempt.
equipo servidor 4000000 "" "" "cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3" SSD
mkdir -p "$TMP/servidor/destino/etc/lazaro"; : > "$TMP/servidor/destino/etc/lazaro/sin-escritorio"
espera "servidor: preempt no aplica sin escritorio" "$(estado servidor preempt)" no-aplica
espera "servidor: nivel v2" "$(af servidor --perfil | sed -n 's/^Nivel x86-64: //p')" v2
salida="$(af servidor --aplicar --raiz "$TMP/servidor/destino")"
espera "servidor: sin parámetros de arranque" "$salida" "LAZARO-AFINADOR-OK "
grep -q lazaro-afinador "$TMP/servidor/destino/etc/default/grub" && mal "servidor: escribió en GRUB sin nada que poner" || ok "servidor: GRUB intacto"

echo
if [ "$fallos" -eq 0 ]; then
	echo "Afinador: $n comprobaciones bien."
else
	echo "Afinador: $fallos de $n comprobaciones fallaron." >&2
	exit 1
fi
