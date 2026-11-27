#!/bin/sh
# prueba-viabilidad.sh: prueba a mano, en un equipo con NVIDIA, la
# arquitectura de docs/nvidia/ARQUITECTURA.md (opción A): módulo de NVIDIA
# compilado con las herramientas de Alpine y Xorg con el espacio de
# usuario de NVIDIA dentro de un sysroot glibc (Debian), con los
# programas musl del sistema como clientes.
#
# NO es parte de la ISO ni del instalador: es la prueba del paso 1. Deja
# todo en sitios propios y --deshacer lo quita.
#
# Antes de empezar:
#   1. Lázaro Linux instalado en el equipo, con internet y unos 3 GB
#      libres en /opt.
#   2. Arrancar SIN nouveau: en el menú de GRUB, "e" sobre la entrada de
#      siempre, añadir modprobe.blacklist=nouveau al final de la línea
#      "linux" y arrancar con Ctrl+X. (No queda guardado.)
#   3. Entrar en una consola de texto (Ctrl+Alt+F2) como root. El paso de
#      Xorg cambia de pantalla y vuelve solo.
#
# Uso (como root):
#   sh nvidia/prueba-viabilidad.sh [opciones] [PASO...]
#
# Pasos (sin pasos: todos, en este orden):
#   modulo           compila e instala el módulo del kernel y lo carga
#   raiz             crea el sysroot Debian en /opt/lazaro-nvidia/raiz
#   espacio-usuario  instala las bibliotecas de NVIDIA en el sysroot
#   gcompat          intenta nvidia-smi con gcompat (solo para anotarlo)
#   xorg             arranca el Xorg del sysroot y prueba GL, Vulkan y un
#                    cliente musl
#   deshacer         quita módulos, firmware, sysroot y ajustes
#
# Opciones:
#   --version V      versión del controlador (por defecto $NVIDIA_VERSION)
#   --modulo M       abierto o cerrado (por defecto: según la tarjeta)
#   --flatpak        en el paso xorg, probar también Flatpak con GL.nvidia
#                    (descarga más de 1 GB)
#
# Informe: /var/log/lazaro-nvidia-prueba.txt (es lo que hay que mandar).

set -eu

NVIDIA_VERSION="${NVIDIA_VERSION:-580.95.05}"
DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"
FLATPAK_RAMA="${FLATPAK_RAMA:-25.08}"
BASE="${LAZARO_NVIDIA_BASE:-/opt/lazaro-nvidia}"
RAIZ="$BASE/raiz"
TRABAJO="$BASE/trabajo"
INFORME="${LAZARO_NVIDIA_INFORME:-/var/log/lazaro-nvidia-prueba.txt}"
MODPROBE_CONF=/etc/modprobe.d/lazaro-nvidia-prueba.conf
PANTALLA=7

modulo=""
flatpak=no
pasos=""

msg() { printf '\n==> %s\n' "$*"; printf '\n==> %s\n' "$*" >> "$INFORME"; }
anota() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$INFORME"; }
die() { printf 'ERROR: %s\n' "$*" >&2; { printf 'ERROR: %s\n' "$*" >> "$INFORME"; } 2>/dev/null || true; exit 1; }
resultado() { anota "RESULTADO $1: $2"; }

# con_avance LOG ORDEN...: ejecuta ORDEN guardando su salida en LOG y,
# mientras dura, muestra cada 15 s la última línea del log, para que la
# pantalla no parezca colgada. Devuelve el estado de ORDEN.
con_avance() {
	log="$1"; shift
	"$@" >> "$log" 2>&1 &
	pid=$!
	t0=$(date +%s)
	while kill -0 "$pid" 2>/dev/null; do
		sleep 15
		kill -0 "$pid" 2>/dev/null || break
		printf '   [%s s] %s\n' "$(( $(date +%s) - t0 ))" "$(tail -n 1 "$log" 2>/dev/null | cut -c1-90)"
	done
	wait "$pid"
}

# --- Comprobaciones -------------------------------------------------------

comprobar() {
	[ "$(id -u)" -eq 0 ] || die "hay que ejecutarlo como root"
	[ "$(uname -m)" = x86_64 ] || die "solo para 64 bits (x86_64)"
	command -v apk >/dev/null 2>&1 || die "no parece Alpine ni Lázaro Linux (falta apk)"
	command -v lspci >/dev/null 2>&1 || apk add -q pciutils
	lspci -n -d 10de: 2>/dev/null | grep -q ' 03[08]' \
		|| die "no se encontró ninguna tarjeta gráfica NVIDIA"
}

tarjeta() {
	lspci -mm -d 10de: 2>/dev/null | awk -F'"' '$2 ~ /VGA|3D/ { print $6; exit }'
}

modulo_por_tarjeta() {
	case "$(tarjeta)" in
		TU*|GA*|GH*|AD*|GB*) echo abierto ;;
		*) echo cerrado ;;
	esac
}

version_mayor() { echo "${NVIDIA_VERSION%%.*}"; }

# --- Descarga del controlador ---------------------------------------------

# RUN y EXTRAIDO se fijan al final, después de leer --version.
descargar() {
	mkdir -p "$TRABAJO"
	apk add -q wget xz zstd tar >/dev/null 2>&1 || true
	if [ ! -s "$RUN" ]; then
		msg "Descargando el controlador $NVIDIA_VERSION"
		wget -O "$RUN.part" \
			"https://us.download.nvidia.com/XFree86/Linux-x86_64/$NVIDIA_VERSION/NVIDIA-Linux-x86_64-$NVIDIA_VERSION.run" \
			|| die "no se pudo descargar la versión $NVIDIA_VERSION (¿existe?)"
		mv "$RUN.part" "$RUN"
	fi
	if [ ! -d "$EXTRAIDO" ]; then
		(cd "$TRABAJO" && sh "$RUN" --extract-only >/dev/null) \
			|| die "no se pudo extraer $RUN"
	fi
}

# --- Paso: módulo del kernel ----------------------------------------------

paso_modulo() {
	[ ! -d /sys/module/nouveau ] || die "nouveau está cargado. Reinicia con modprobe.blacklist=nouveau (ver el comienzo de este archivo)."
	kver="$(uname -r)"
	sabor="${kver##*-}"
	msg "Módulo $modulo $NVIDIA_VERSION para el kernel $kver"
	anota "Tarjeta: $(tarjeta)"

	apk add -q build-base bash perl elfutils-dev "linux-$sabor-dev" wget \
		|| die "no se pudieron instalar las herramientas de compilación"
	[ -d "/lib/modules/$kver/build" ] \
		|| die "no están los encabezados de $kver. Si el kernel se actualizó sin reiniciar, reinicia y repite."

	descargar
	case "$modulo" in
		abierto) fuente="$EXTRAIDO/kernel-open" ;;
		cerrado) fuente="$EXTRAIDO/kernel" ;;
		*) die "módulo desconocido: $modulo" ;;
	esac
	[ -d "$fuente" ] || die "esta versión no trae $fuente (el módulo abierto existe desde la 515)"

	inicio=$(date +%s)
	make -C "$fuente" SYSSRC="/lib/modules/$kver/build" -j"$(nproc)" modules \
		> "$TRABAJO/compilacion.log" 2>&1 || {
		errores=$(grep -m 5 -A 3 'error:' "$TRABAJO/compilacion.log" || tail -n 40 "$TRABAJO/compilacion.log")
		anota "$errores"
		resultado modulo-compila FALLA
		anota "Si el error es de una función del kernel (argumentos, tipos), esta versión del controlador es anterior al kernel $kver: prueba una más nueva con --version."
		die "falló la compilación (ver $TRABAJO/compilacion.log)"
	}
	resultado modulo-compila "PASA en $(( $(date +%s) - inicio )) s con gcc $(gcc -dumpversion) y musl"

	mkdir -p "/lib/modules/$kver/extra/nvidia"
	cp "$fuente"/*.ko "/lib/modules/$kver/extra/nvidia/"
	depmod -a "$kver"

	if [ -d "$EXTRAIDO/firmware" ]; then
		mkdir -p "/lib/firmware/nvidia/$NVIDIA_VERSION"
		cp "$EXTRAIDO"/firmware/*.bin "/lib/firmware/nvidia/$NVIDIA_VERSION/"
	fi

	{
		echo "# Prueba de viabilidad de NVIDIA (nvidia/prueba-viabilidad.sh)."
		echo "blacklist nouveau"
		if [ "$(version_mayor)" -ge 545 ]; then
			echo "options nvidia-drm modeset=1 fbdev=1"
		else
			echo "options nvidia-drm modeset=1"
		fi
	} > "$MODPROBE_CONF"

	modprobe nvidia || { dmesg | grep -i nvidia | tail -n 20 >> "$INFORME"; resultado modulo-carga FALLA; die "el módulo no cargó (ver dmesg)"; }
	modprobe nvidia-modeset
	modprobe nvidia-drm
	modprobe nvidia-uvm || anota "aviso: nvidia-uvm no cargó (solo afecta a CUDA)"
	crear_dispositivos
	anota "$(head -n 1 /proc/driver/nvidia/version)"
	resultado modulo-carga PASA
}

# Lo que normalmente hace nvidia-modprobe o una regla de udev.
crear_dispositivos() {
	i=0
	for _g in /proc/driver/nvidia/gpus/*; do
		[ -e "/dev/nvidia$i" ] || mknod -m 666 "/dev/nvidia$i" c 195 "$i"
		i=$((i + 1))
	done
	[ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c 195 255
	[ -e /dev/nvidia-modeset ] || mknod -m 666 /dev/nvidia-modeset c 195 254
	uvm=$(awk '$2 == "nvidia-uvm" { print $1 }' /proc/devices)
	if [ -n "$uvm" ]; then
		[ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$uvm" 0
		[ -e /dev/nvidia-uvm-tools ] || mknod -m 666 /dev/nvidia-uvm-tools c "$uvm" 1
	fi
}

# --- Montajes del sysroot -------------------------------------------------

montado() { grep -q " $1 " /proc/mounts; }

montar() {
	for d in dev dev/pts proc sys run/udev; do
		mkdir -p "$RAIZ/$d"
		montado "$RAIZ/$d" || mount -o bind "/$d" "$RAIZ/$d"
	done
	mkdir -p /tmp/.X11-unix "$RAIZ/tmp/.X11-unix"
	chmod 1777 /tmp/.X11-unix
	montado "$RAIZ/tmp/.X11-unix" || mount -o bind /tmp/.X11-unix "$RAIZ/tmp/.X11-unix"
}

desmontar() {
	for d in tmp/.X11-unix run/udev sys proc dev/pts dev; do
		! montado "$RAIZ/$d" || umount "$RAIZ/$d" || umount -l "$RAIZ/$d" || true
	done
}

en_raiz() { chroot "$RAIZ" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root "$@"; }

# --- Paso: sysroot Debian -------------------------------------------------

paso_raiz() {
	msg "Sysroot Debian $DEBIAN_SUITE en $RAIZ"
	if [ -x "$RAIZ/usr/bin/Xorg" ]; then
		anota "ya existe, se usa el que hay"
		return 0
	fi
	libre=$(df -Pm "$(dirname "$BASE")" | awk 'NR == 2 { print $4 }')
	[ "${libre:-0}" -ge 3000 ] || die "hacen falta 3 GB libres en $(dirname "$BASE") (hay ${libre} MB)"

	apk add -q debootstrap binutils wget || die "no se pudo instalar debootstrap"
	apk add -q debian-archive-keyring 2>/dev/null || true
	llave=""
	for k in /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/debootstrap/keyrings/debian-archive-keyring.gpg; do
		[ -r "$k" ] && llave="--keyring=$k" && break
	done
	if [ -z "$llave" ]; then
		llave="--no-check-gpg"
		anota "aviso: sin llavero de Debian; se descarga por HTTPS sin comprobar firmas (solo para la prueba)"
	fi

	mkdir -p "$RAIZ" "$TRABAJO"
	inicio=$(date +%s)
	# shellcheck disable=SC2086
	: > "$TRABAJO/debootstrap.log"
	con_avance "$TRABAJO/debootstrap.log" debootstrap --variant=minbase $llave \
		--include=xserver-xorg-core,xserver-xorg-input-libinput,libglvnd0,libgl1,libglx0,libegl1,libgles2,libvulkan1,mesa-utils,vulkan-tools,x11-xserver-utils,kmod,pkg-config,xz-utils,zstd \
		"$DEBIAN_SUITE" "$RAIZ" "$DEBIAN_MIRROR" || {
		tail -n 40 "$TRABAJO/debootstrap.log" >> "$INFORME" 2>/dev/null || true
		resultado raiz FALLA
		die "falló debootstrap (ver $TRABAJO/debootstrap.log)"
	}
	en_raiz apt-get clean >/dev/null 2>&1 || true
	resultado raiz "PASA en $(( $(date +%s) - inicio )) s, ocupa $(du -sm "$RAIZ" | cut -f1) MB"
}

# --- Paso: espacio de usuario de NVIDIA ------------------------------------

paso_espacio_usuario() {
	msg "Espacio de usuario de NVIDIA $NVIDIA_VERSION en el sysroot"
	[ -x "$RAIZ/usr/bin/Xorg" ] || die "falta el sysroot (paso raiz)"
	descargar
	cp "$RUN" "$RAIZ/root/nvidia.run"
	montar
	set -- --accept-license --ui=none --no-questions --no-kernel-module \
		--no-install-libglvnd --no-x-check --no-nouveau-check \
		--no-distro-scripts --no-systemd --no-rpms --no-backup \
		--no-check-for-alternate-installs
	: > "$TRABAJO/instalador.log"
	if con_avance "$TRABAJO/instalador.log" en_raiz /bin/sh /root/nvidia.run "$@"; then
		resultado espacio-usuario PASA
	else
		cp "$RAIZ/var/log/nvidia-installer.log" "$TRABAJO/" 2>/dev/null || true
		tail -n 40 "$RAIZ/var/log/nvidia-installer.log" >> "$INFORME" 2>/dev/null || true
		desmontar
		resultado espacio-usuario FALLA
		die "falló el instalador de NVIDIA (ver $TRABAJO/nvidia-installer.log)"
	fi
	rm -f "$RAIZ/root/nvidia.run"

	mkdir -p "$RAIZ/etc/X11/xorg.conf.d"
	cat > "$RAIZ/etc/X11/xorg.conf.d/10-nvidia.conf" <<-'EOF'
	Section "Device"
		Identifier "NVIDIA"
		Driver "nvidia"
	EndSection
	EOF

	if en_raiz nvidia-smi >> "$INFORME" 2>&1; then
		resultado nvidia-smi PASA
	else
		resultado nvidia-smi FALLA
	fi
	desmontar
}

# --- Paso: gcompat (solo para documentar) ---------------------------------

paso_gcompat() {
	msg "nvidia-smi del sysroot con gcompat, sin glibc"
	[ -x "$RAIZ/usr/bin/nvidia-smi" ] || die "falta el espacio de usuario (paso espacio-usuario)"
	instalado=no
	apk info -e gcompat >/dev/null 2>&1 || { apk add -q gcompat && instalado=si; }
	tmp=$(mktemp -d)
	find "$RAIZ/usr/lib" -name 'libnvidia-ml.so*' -exec cp -P {} "$tmp/" \;
	if LD_LIBRARY_PATH="$tmp" "$RAIZ/usr/bin/nvidia-smi" > "$tmp/salida" 2>&1; then
		resultado gcompat "nvidia-smi funciona con gcompat"
	else
		resultado gcompat "nvidia-smi NO funciona con gcompat (lo esperado)"
	fi
	head -n 15 "$tmp/salida" >> "$INFORME"
	rm -rf "$tmp"
	[ "$instalado" = no ] || apk del -q gcompat
}

# --- Paso: Xorg del sysroot -----------------------------------------------

paso_xorg() {
	msg "Xorg del sysroot en la pantalla :$PANTALLA (vt$PANTALLA)"
	[ -x "$RAIZ/usr/lib/xorg/modules/drivers/nvidia_drv.so" ] \
		|| die "falta nvidia_drv.so en el sysroot (paso espacio-usuario)"
	[ -d /sys/module/nvidia_drm ] || die "el módulo no está cargado (paso modulo)"
	crear_dispositivos
	apk add -q xdpyinfo xterm || true
	apk add -q mesa-utils 2>/dev/null || apk add -q mesa-demos 2>/dev/null || true
	apk add -q vulkan-tools 2>/dev/null || true

	montar
	vt_antes=$(fgconsole 2>/dev/null || echo 2)
	en_raiz /usr/bin/Xorg ":$PANTALLA" "vt$PANTALLA" -nolisten tcp -noreset \
		-logfile "/var/log/Xorg.$PANTALLA.log" > /dev/null 2>&1 &
	xpid=$!
	i=0
	while [ ! -S "/tmp/.X11-unix/X$PANTALLA" ] && [ $i -lt 30 ]; do
		kill -0 "$xpid" 2>/dev/null || break
		sleep 1; i=$((i + 1))
	done

	if [ -S "/tmp/.X11-unix/X$PANTALLA" ]; then
		resultado xorg-arranca PASA
		export DISPLAY=":$PANTALLA"

		gl=$(en_raiz DISPLAY=":$PANTALLA" glxinfo -B 2>&1 || true)
		printf '%s\n' "$gl" | grep -E 'vendor string|renderer string|core profile version' >> "$INFORME" || true
		if printf '%s\n' "$gl" | grep -q 'OpenGL vendor string: NVIDIA'; then
			resultado opengl-sysroot PASA
		else
			resultado opengl-sysroot FALLA
		fi

		vk=$(en_raiz DISPLAY=":$PANTALLA" vulkaninfo --summary 2>&1 || true)
		printf '%s\n' "$vk" | grep -E 'deviceName|driverName|driverInfo' >> "$INFORME" || true
		if printf '%s\n' "$vk" | grep -q 'driverName *= *NVIDIA'; then
			resultado vulkan-sysroot PASA
		else
			resultado vulkan-sysroot FALLA
		fi

		if xdpyinfo > /dev/null 2>&1; then
			resultado cliente-musl "PASA (xdpyinfo de Alpine se conecta)"
		else
			resultado cliente-musl FALLA
		fi
		if command -v glxinfo >/dev/null 2>&1; then
			anota "glxinfo de Alpine (musl): $(glxinfo -B 2>&1 | grep 'renderer string' || echo 'sin GLX')"
		fi

		# Para verlo con los propios ojos: 10 s de vkcube y un xterm musl.
		en_raiz DISPLAY=":$PANTALLA" timeout 10 vkcube > /dev/null 2>&1 &
		timeout 10 xterm -geometry 60x5+20+20 -e sh -c 'echo "xterm de Alpine (musl) en el Xorg del sysroot"; sleep 9' 2>/dev/null &
		sleep 11

		[ "$flatpak" = no ] || prueba_flatpak
	else
		resultado xorg-arranca FALLA
	fi

	grep -E '\(EE\)|NVIDIA\(0\)|Using input driver' "$RAIZ/var/log/Xorg.$PANTALLA.log" 2>/dev/null \
		| head -n 40 >> "$INFORME" || true
	kill "$xpid" 2>/dev/null || true
	sleep 2
	desmontar
	chvt "$vt_antes" 2>/dev/null || true
}

prueba_flatpak() {
	msg "Flatpak con GL.nvidia"
	apk add -q flatpak || { resultado flatpak "FALLA (no se pudo instalar flatpak)"; return 0; }
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	ext="org.freedesktop.Platform.GL.nvidia-$(echo "$NVIDIA_VERSION" | tr . -)"
	if ! con_avance "$TRABAJO/flatpak.log" flatpak install -y --noninteractive flathub "$ext"; then
		resultado flatpak "FALLA (Flathub no tiene $ext)"
		return 0
	fi
	con_avance "$TRABAJO/flatpak.log" flatpak install -y --noninteractive flathub "org.freedesktop.Sdk//$FLATPAK_RAMA" || true
	vk=$(flatpak run --command=vulkaninfo "org.freedesktop.Sdk//$FLATPAK_RAMA" --summary 2>&1 || true)
	printf '%s\n' "$vk" | grep -E 'deviceName|driverName' >> "$INFORME" || true
	if printf '%s\n' "$vk" | grep -q 'driverName *= *NVIDIA'; then
		resultado flatpak PASA
	else
		resultado flatpak "FALLA o sin vulkaninfo en el Sdk (ver el informe)"
	fi
}

# --- Paso: deshacer -------------------------------------------------------

paso_deshacer() {
	msg "Quitando todo lo de la prueba"
	desmontar
	for m in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do
		[ ! -d "/sys/module/$m" ] || rmmod "$m" 2>/dev/null || anota "aviso: no se pudo descargar $m (se va al reiniciar)"
	done
	for d in /lib/modules/*/extra/nvidia; do
		[ -d "$d" ] || continue
		rm -rf "$d"
		k="${d#/lib/modules/}"; depmod -a "${k%%/*}"
	done
	rm -rf "/lib/firmware/nvidia/$NVIDIA_VERSION" "$MODPROBE_CONF"
	rm -f /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools
	rm -rf "$BASE"
	anota "listo: al reiniciar normal, el equipo vuelve a nouveau"
}

# --- Principal ------------------------------------------------------------

while [ $# -gt 0 ]; do
	case "$1" in
		--version) NVIDIA_VERSION="$2"; shift 2 ;;
		--modulo) modulo="$2"; shift 2 ;;
		--flatpak) flatpak=si; shift ;;
		modulo|raiz|espacio-usuario|gcompat|xorg|deshacer) pasos="$pasos $1"; shift ;;
		-h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "opción o paso desconocido: $1 (ver --help)" ;;
	esac
done
RUN="$TRABAJO/NVIDIA-Linux-x86_64-$NVIDIA_VERSION.run"
EXTRAIDO="$TRABAJO/NVIDIA-Linux-x86_64-$NVIDIA_VERSION"
[ -n "$pasos" ] || pasos="modulo raiz espacio-usuario gcompat xorg"

[ "$(id -u)" -eq 0 ] || die "hay que ejecutarlo como root"
mkdir -p "$(dirname "$INFORME")"
comprobar
[ -n "$modulo" ] || modulo="$(modulo_por_tarjeta)"
{
	echo "=== Prueba de viabilidad NVIDIA en Lázaro Linux, $(date) ==="
	echo "Pasos:$pasos | versión $NVIDIA_VERSION | módulo $modulo | kernel $(uname -r)"
	grep PRETTY_NAME /etc/os-release 2>/dev/null || true
} >> "$INFORME"

for p in $pasos; do
	case "$p" in
		modulo) paso_modulo ;;
		raiz) paso_raiz ;;
		espacio-usuario) paso_espacio_usuario ;;
		gcompat) paso_gcompat ;;
		xorg) paso_xorg ;;
		deshacer) paso_deshacer ;;
	esac
done

msg "Resumen"
grep '^RESULTADO' "$INFORME" | tail -n 12
printf '\nInforme completo: %s\n' "$INFORME"
