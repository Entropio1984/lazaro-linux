#!/bin/sh -e
# Genera el apkovl (la configuración) de la sesión live de Lázaro Linux.
# Lo ejecuta mkimage.sh bajo fakeroot, con el nombre de host como $1.
# Variables que deja build.sh / el perfil:
#   LAZARO_LIVE_DIR  carpeta live/ (archivos a copiar tal cual)
#   LAZARO_SCRIPT    ruta a desktop-postinstall.sh
#   LAZARO_VERSION_ENV  archivo con la versión de Alpine y de la ISO
#   LAZARO_WORLD     paquetes de la sesión live
#   LAZARO_PUBKEY    llave pública que firma el repositorio de la ISO

HOSTNAME="$1"
[ -n "$HOSTNAME" ] || { echo "uso: $0 nombre-de-host" >&2; exit 1; }
: "${LAZARO_LIVE_DIR:?falta LAZARO_LIVE_DIR}"
: "${LAZARO_SCRIPT:?falta LAZARO_SCRIPT}"
: "${LAZARO_VERSION_ENV:?falta LAZARO_VERSION_ENV}"
: "${LAZARO_WORLD:?falta LAZARO_WORLD}"
: "${LAZARO_PUBKEY:?falta LAZARO_PUBKEY}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

# Archivos fijos de la sesión live (Calamares, servicios, accesos).
cp -a "$LAZARO_LIVE_DIR"/. "$tmp"/
chown -R root:root "$tmp"
chmod 0755 "$tmp"/usr/sbin/* "$tmp"/etc/init.d/*

# Edición Completa: todo viene en el USB. Se corrigen los textos que
# dicen que GNOME, Plasma, las traducciones o las aplicaciones de Flathub
# se descargan. Cada cambio se comprueba: si un texto original cambió, la
# compilación avisa en vez de dejar el mensaje viejo.
textos_completa() {
	tc_cal="$tmp/etc/calamares/modules"
	tc_qml="$tmp/usr/share/calamares/branding/lazaro/show.qml"
	tc_cambiar() { # ARCHIVO TEXTO_VIEJO TEXTO_NUEVO
		grep -qF -- "$2" "$1" || { echo "genapkovl-lazaro: no está el texto '$2' en $1" >&2; exit 1; }
		awk -v viejo="$2" -v nuevo="$3" '{
			resto = $0; hecho = ""
			while ((i = index(resto, viejo)) > 0) {
				hecho = hecho substr(resto, 1, i - 1) nuevo
				resto = substr(resto, i + length(viejo))
			}
			print hecho resto
		}' "$1" > "$1.nuevo"
		mv "$1.nuevo" "$1"
	}
	tc_cambiar "$tc_cal/packagechooser-escritorio.conf" "Needs internet." "Installs without internet."
	tc_cambiar "$tc_cal/packagechooser-escritorio.conf" "Necesita internet." "Se instala sin internet desde el USB."
	tc_cambiar "$tc_cal/packagechooser-escritorio.conf" \
		"Installs without internet; its bar and graphical login arrive once online." "Installs without internet."
	tc_cambiar "$tc_cal/packagechooser-escritorio.conf" \
		"desde el USB; la barra y la pantalla de inicio gráfica llegan al conectarse a internet." "desde el USB."
	tc_cambiar "$tc_cal/netinstall.conf" \
		"Viene en el USB (en español; otro idioma se descarga)." "Viene en el USB, en todos los idiomas."
	tc_cambiar "$tc_cal/netinstall.conf" \
		"Aplicaciones Flatpak (se instalan solas después del primer arranque, con internet)" \
		"Aplicaciones Flatpak (OnlyOffice y Brave vienen en el USB)"
	tc_cambiar "$tc_cal/netinstall.conf" \
		"Vienen de Flathub. Se descargan en segundo plano unos minutos después de encender el equipo conectado a internet." \
		"Vienen de Flathub. OnlyOffice y Brave se instalan desde el USB, sin internet. Google Chrome no se puede incluir: se descarga solo después del primer arranque, con internet."
	tc_cambiar "$tc_cal/netinstall.conf" \
		"(paquete comunitario de Flathub, no oficial de Google)." \
		"(paquete comunitario de Flathub, no oficial de Google). Necesita internet."
	tc_cambiar "$tc_qml" \
		"Las aplicaciones de Flathub que marcaste (OnlyOffice, Chrome, Brave) se instalan solas en segundo plano unos minutos después del primer arranque, cuando el equipo tenga internet." \
		"OnlyOffice y Brave se instalan desde el USB. Google Chrome, si lo marcaste, se instala solo en segundo plano unos minutos después del primer arranque, cuando el equipo tenga internet."
	tc_cambiar "$tc_qml" \
		"Si instalaste sin internet, la configuración final se completa sola la primera vez que el equipo se conecte a una red." \
		"Esta edición trae todo en el USB: el sistema queda completo aunque no haya internet. Solo Google Chrome espera a que el equipo se conecte."
}
[ "${LAZARO_EDICION:-ligera}" != completa ] || textos_completa

# El script del usuario se copia a la ISO desde la raíz del repositorio:
# así hay una sola copia que mantener.
install -Dm755 "$LAZARO_SCRIPT" "$tmp"/usr/share/lazaro/desktop-postinstall.sh
install -Dm644 "$LAZARO_VERSION_ENV" "$tmp"/usr/share/lazaro/version.env

# El índice del repositorio de la ISO lo firma nuestra llave, no la de
# Alpine: sin ella, setup-disk no podría instalar desde la ISO.
install -Dm644 "$LAZARO_PUBKEY" "$tmp/etc/apk/keys/$(basename "$LAZARO_PUBKEY")"

echo "$HOSTNAME" > "$tmp"/etc/hostname
mkdir -p "$tmp"/etc/apk
printf '%s\n' $LAZARO_WORLD > "$tmp"/etc/apk/world

# Igual que "setup-devd udev" (alpine-conf): eudev en lugar de mdev,
# necesario para Xorg y para que Calamares vea los discos.
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add lazaro-graficas boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add udev-postmount default
rc_add dbus default
rc_add elogind default
rc_add networkmanager default
rc_add lazaro-live default
rc_add lightdm default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc usr | gzip -9n > "$HOSTNAME".apkovl.tar.gz
