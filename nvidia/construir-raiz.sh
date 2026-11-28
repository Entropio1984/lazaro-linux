#!/bin/sh
# construir-raiz.sh: arma el sysroot glibc de NVIDIA (Debian, Xorg y el
# espacio de usuario de NVIDIA) y lo empaqueta en un .tar.zst para la ISO
# Completa (docs/nvidia/ARQUITECTURA.md, 4.2).
#
# Corre en un Debian o un Ubuntu (el CI de GitHub), como root, con
# debootstrap, debian-archive-keyring, wget y zstd. No necesita una
# tarjeta NVIDIA: el instalador de NVIDIA se ejecuta sin el módulo del
# kernel, que va aparte (paquetes/nvidia-open).
#
#   sudo sh nvidia/construir-raiz.sh [--version V] [--salida DIR]
#
# Deja en DIR (por defecto salida/):
#   lazaro-nvidia-raiz-V.tar.zst    el sysroot, para /opt/lazaro-nvidia/raiz
#   lazaro-nvidia-raiz-V.tar.zst.sha256

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Misma versión que la tabla de ramas: el módulo y las bibliotecas tienen
# que coincidir exactamente.
NVIDIA_VERSION="$(sed -n 's/^VERSION_ACTUAL=//p' "$DIR/live/usr/sbin/lazaro-nvidia")"
DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
SALIDA="$DIR/salida"

while [ $# -gt 0 ]; do
	case "$1" in
		--version) NVIDIA_VERSION="$2"; shift 2 ;;
		--salida) SALIDA="$2"; shift 2 ;;
		-h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "opción desconocida: $1" >&2; exit 2 ;;
	esac
done

msg() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "hay que ejecutarlo como root"
[ -n "$NVIDIA_VERSION" ] || die "no se encontró VERSION_ACTUAL en live/usr/sbin/lazaro-nvidia"
for p in debootstrap wget zstd chroot; do
	command -v "$p" >/dev/null 2>&1 || die "falta $p"
done
LLAVERO=/usr/share/keyrings/debian-archive-keyring.gpg
[ -r "$LLAVERO" ] || die "falta $LLAVERO (paquete debian-archive-keyring)"

TRABAJO="$(mktemp -d)"
RAIZ="$TRABAJO/raiz"
NOMBRE="lazaro-nvidia-raiz-$NVIDIA_VERSION.tar.zst"

montado() { grep -q " $1 " /proc/mounts; }
desmontar() {
	for d in sys proc dev/pts dev; do
		! montado "$RAIZ/$d" || umount "$RAIZ/$d" || umount -l "$RAIZ/$d" || true
	done
}
limpiar() { desmontar; rm -rf "$TRABAJO"; }
trap limpiar EXIT INT TERM

en_raiz() { chroot "$RAIZ" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root "$@"; }

msg "Debian $DEBIAN_SUITE mínimo con Xorg"
# Lo mismo que se probó en la RTX 3060 con nvidia/prueba-viabilidad.sh.
# mesa-utils y vulkan-tools (glxinfo, vulkaninfo) quedan para diagnosticar.
# Un debootstrap más viejo que la versión de Debian no trae su guion:
# todas las de Debian desde buster usan el mismo que sid.
guion=""
[ -e "/usr/share/debootstrap/scripts/$DEBIAN_SUITE" ] || guion=/usr/share/debootstrap/scripts/sid
intento=1
# shellcheck disable=SC2086
until debootstrap --variant=minbase --keyring="$LLAVERO" \
	--include=xserver-xorg-core,xserver-xorg-input-libinput,libglvnd0,libgl1,libglx0,libegl1,libgles2,libvulkan1,mesa-utils,vulkan-tools,x11-xserver-utils,kmod,pkg-config,xz-utils \
	"$DEBIAN_SUITE" "$RAIZ" "$DEBIAN_MIRROR" $guion; do
	[ "$intento" -lt 3 ] || die "falló debootstrap 3 veces"
	intento=$((intento + 1))
	echo "debootstrap falló; intento $intento de 3"
	sleep 10
done
[ -x "$RAIZ/usr/bin/Xorg" ] || die "debootstrap terminó sin Xorg"

msg "Espacio de usuario de NVIDIA $NVIDIA_VERSION"
url="https://us.download.nvidia.com/XFree86/Linux-x86_64/$NVIDIA_VERSION/NVIDIA-Linux-x86_64-$NVIDIA_VERSION.run"
wget -q -c --timeout=30 --tries=10 --waitretry=5 -O "$TRABAJO/nvidia.run" "$url" \
	|| die "no se pudo descargar $url"
cp "$TRABAJO/nvidia.run" "$RAIZ/root/nvidia.run"
for d in dev dev/pts proc sys; do
	mkdir -p "$RAIZ/$d"
	mount -o bind "/$d" "$RAIZ/$d"
done
en_raiz /bin/sh /root/nvidia.run --accept-license --ui=none --no-questions \
	--no-kernel-module --no-install-libglvnd --no-x-check --no-nouveau-check \
	--no-distro-scripts --no-systemd --no-rpms --no-backup \
	--no-check-for-alternate-installs \
	--glvnd-egl-config-path=/usr/share/glvnd/egl_vendor.d || {
	tail -n 60 "$RAIZ/var/log/nvidia-installer.log" >&2 || true
	die "falló el instalador de NVIDIA"
}
desmontar
rm -f "$RAIZ/root/nvidia.run"

# Sin pkg-config de libglvnd, el instalador no sabe dónde va la
# configuración de EGL (10_nvidia.json) y la omite con un aviso: por eso
# se le da la ruta y aquí se comprueba, junto con la de Vulkan.
for f in usr/lib/xorg/modules/drivers/nvidia_drv.so usr/bin/nvidia-smi usr/bin/nvidia-persistenced \
	usr/share/glvnd/egl_vendor.d/10_nvidia.json; do
	[ -e "$RAIZ/$f" ] || die "el instalador no dejó /$f"
done
# Las bibliotecas de NVIDIA tienen que encontrar todo lo que piden dentro
# del sysroot (sin la GPU no se puede probar más que esto).
[ -n "$(cd "$RAIZ" && find usr/share/vulkan etc/vulkan -name 'nvidia_icd*.json' 2>/dev/null)" ] \
	|| die "el instalador no dejó la configuración de Vulkan (nvidia_icd.json)"
glx=$(cd "$RAIZ" && find usr/lib -name 'libGLX_nvidia.so.*' -type f | head -n 1)
[ -n "$glx" ] || die "el instalador no dejó libGLX_nvidia.so"
faltan=$(for f in "/$glx" /usr/lib/xorg/modules/drivers/nvidia_drv.so; do
	en_raiz ldd "$f" | grep 'not found' || true
done)
[ -z "$faltan" ] || die "faltan bibliotecas en el sysroot: $faltan"

# En /usr/share y no en /etc: /etc/X11/xorg.conf.d es la del sistema
# (el teclado), que nvidia-raiz monta encima.
mkdir -p "$RAIZ/usr/share/X11/xorg.conf.d"
cat > "$RAIZ/usr/share/X11/xorg.conf.d/10-lazaro-nvidia.conf" <<-'EOT'
Section "Device"
	Identifier "NVIDIA"
	Driver "nvidia"
EndSection
EOT
cat > "$RAIZ/etc/lazaro-nvidia" <<-EOT
VERSION=$NVIDIA_VERSION
DEBIAN=$DEBIAN_SUITE
FECHA=$(date -u +%Y-%m-%d)
EOT

msg "Limpieza"
en_raiz apt-get clean >/dev/null 2>&1 || true
rm -rf "$RAIZ"/var/lib/apt/lists/* "$RAIZ"/var/cache/* "$RAIZ"/var/log/* \
	"$RAIZ"/usr/share/doc/* "$RAIZ"/usr/share/man/* "$RAIZ"/usr/share/info/* \
	"$RAIZ"/usr/share/locale/* "$RAIZ"/tmp/* "$RAIZ"/root/.cache
echo "sysroot: $(du -sm "$RAIZ" | cut -f1) MB"

msg "Empaquetando $NOMBRE"
mkdir -p "$SALIDA"
tar --numeric-owner --xattrs -C "$RAIZ" -cf - . | zstd -q -19 -T0 -o "$SALIDA/$NOMBRE" -f
(cd "$SALIDA" && sha256sum "$NOMBRE" > "$NOMBRE.sha256")
echo "$SALIDA/$NOMBRE: $(du -m "$SALIDA/$NOMBRE" | cut -f1) MB"
