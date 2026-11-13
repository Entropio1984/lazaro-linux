#!/bin/sh -e
# Genera el apkovl (la configuración) de la sesión live de Lázaro Linux.
# Lo ejecuta mkimage.sh bajo fakeroot, con el nombre de host como $1.
# Variables que deja build.sh / el perfil:
#   LAZARO_LIVE_DIR  carpeta live/ (archivos a copiar tal cual)
#   LAZARO_DATOS_HW  datos generados al compilar (huellas, firmware Intel)
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
[ ! -d "${LAZARO_DATOS_HW:-}" ] || cp -a "$LAZARO_DATOS_HW"/. "$tmp"/
chown -R root:root "$tmp"
chmod 0755 "$tmp"/usr/sbin/* "$tmp"/usr/bin/* "$tmp"/etc/init.d/*

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

# ISO de 32 bits: solo XFCE, LXQt y "Sin escritorio"; sin Flatpak (Flathub
# no tiene aplicaciones de 32 bits); NetSurf va siempre y Firefox pasa a
# ser una casilla. Se quitan de las pantallas de Calamares las opciones
# que no existen y se comprueba que quedó lo esperado.
textos_32() {
	t3_cal="$tmp/etc/calamares/modules"
	awk '
		/^    - id:/ { ver = ($3 == "xfce" || $3 == "lxqt" || $3 == "ninguno") }
		/^    - id:/ || en_items { en_items = 1; if (ver) print; next }
		{ print }
	' "$t3_cal/packagechooser-escritorio.conf" > "$t3_cal/escritorio.nuevo"
	mv "$t3_cal/escritorio.nuevo" "$t3_cal/packagechooser-escritorio.conf"
	[ "$(grep -c '^    - id:' "$t3_cal/packagechooser-escritorio.conf")" = 3 ] ||
		{ echo "genapkovl-lazaro: la lista de escritorios de 32 bits no quedó con 3 opciones" >&2; exit 1; }
	# Software adicional: fuera el grupo de Flatpak (es el último) y entra
	# Firefox, marcado, después de LibreOffice.
	awk '
		/^    - name: "Aplicaciones Flatpak/ { fuera = 1 }
		fuera { next }
		{ print }
		END {
			print "          - name: \"Firefox\""
			print "            description: \"Navegador completo: abre el banco, el correo y los sitios modernos que NetSurf no puede. Es el programa más pesado; con 1 GB de memoria o menos conviene usarlo con pocas pestañas.\""
			print "            selected: true"
			print "            packages: [ firefox ]"
		}
	' "$t3_cal/netinstall.conf" > "$t3_cal/netinstall.nuevo"
	mv "$t3_cal/netinstall.nuevo" "$t3_cal/netinstall.conf"
	! grep -qi 'flatpak' "$t3_cal/netinstall.conf" || sed -i '/^#/!{/[Ff]latpak/d}' "$t3_cal/netinstall.conf"
	grep -q 'packages: \[ firefox \]' "$t3_cal/netinstall.conf" ||
		{ echo "genapkovl-lazaro: no quedó la casilla de Firefox en netinstall.conf" >&2; exit 1; }
	sed -i \
		-e 's/Firefox is always installed\./NetSurf, a light browser, is always installed./' \
		-e 's/Firefox se instala siempre\./NetSurf, un navegador liviano, se instala siempre./' \
		"$t3_cal/netinstall.conf"
	grep -q 'NetSurf, un navegador liviano' "$t3_cal/netinstall.conf" ||
		{ echo "genapkovl-lazaro: no se pudo cambiar el título de netinstall.conf" >&2; exit 1; }
	# Sin estas herramientas en la live, lazaro-instalar no las copia al
	# sistema instalado y la Bienvenida no muestra sus botones.
	rm -f "$tmp/usr/sbin/lazaro-kernel" "$tmp/usr/sbin/lazaro-flatpak" \
		"$tmp/usr/share/lazaro/lazaro-kernel.initd" \
		"$tmp/usr/share/lazaro/bienvenida/funciones/34-kernel.conf" \
		"$tmp/usr/share/lazaro/bienvenida/funciones/22-flatpak.conf"
}
[ "${ALPINE_ARCH:-x86_64}" != x86 ] || textos_32

# El script del usuario se copia a la ISO desde la raíz del repositorio:
# así hay una sola copia que mantener.
install -Dm755 "$LAZARO_SCRIPT" "$tmp"/usr/share/lazaro/desktop-postinstall.sh
install -Dm644 "$LAZARO_VERSION_ENV" "$tmp"/usr/share/lazaro/version.env

# El instalador muestra el número de versión de config.env (ISO_VERSION),
# no uno escrito a mano en branding.desc.
gv_version="$(sed -n 's/^ISO_VERSION="\(.*\)"$/\1/p' "$LAZARO_VERSION_ENV")"
gv_branding="$tmp/usr/share/calamares/branding/lazaro/branding.desc"
if [ -n "$gv_version" ] && [ -f "$gv_branding" ]; then
	sed -i "/[vV]ersion[A-Za-z]*:/ s/[0-9][0-9.]*\"\$/$gv_version\"/" "$gv_branding"
fi

# Manual de Lázaro (PDF): lo compila GitHub Actions (manual/compilar.sh)
# antes de la ISO. En una compilación local sin el PDF, la ISO sale sin
# manual y sin su acceso.
if [ -s "${LAZARO_DIR:-}/manual/lazaro-manual.pdf" ]; then
	install -Dm644 "$LAZARO_DIR/manual/lazaro-manual.pdf" "$tmp"/usr/share/doc/lazaro/manual-lazaro.pdf
else
	echo "genapkovl-lazaro: AVISO: no está manual/lazaro-manual.pdf; la ISO va sin el manual (compílalo con manual/compilar.sh)" >&2
	rm -f "$tmp"/usr/share/applications/lazaro-manual.desktop "$tmp"/usr/bin/lazaro-manual
fi

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
rc_add lazaro-zram boot
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
