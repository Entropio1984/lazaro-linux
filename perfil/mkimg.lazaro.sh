# shellcheck shell=sh
# Perfil de mkimage.sh (aports/scripts) para la ISO de Lázaro Linux.
# build.sh lo copia a ~/.mkimage/ junto con genapkovl-lazaro.sh.
#
# Dos listas de paquetes:
#  - LAZARO_LIVE: lo que se instala en RAM al arrancar la sesión live
#    (escritorio XFCE, red, Calamares). Va en /etc/apk/world del apkovl.
#  - apks: todo lo que se copia al repositorio de la ISO. Incluye lo
#    anterior y además lo que necesita el sistema instalado sin internet
#    (sistema base, XFCE completo, firmware común en portátiles viejos,
#    programas adicionales de Alpine).

# Escritorio de la sesión live = lo que instala "setup-desktop xfce" en
# alpine-conf (verificado en la etiqueta 3.22.0, la de Alpine 3.24).
# 32 bits (ALPINE_ARCH=x86): el navegador de la sesión de prueba es
# NetSurf (unos 30 MB de memoria) en vez de Firefox, que es el programa
# más pesado de la live: en estos equipos la memoria es lo que falta.
# Con él va evince, porque NetSurf no abre PDF y el manual es un PDF.
LAZARO_ARCH="${ALPINE_ARCH:-x86_64}"
LAZARO_NAVEGADOR_LIVE=firefox
[ "$LAZARO_ARCH" != x86 ] || LAZARO_NAVEGADOR_LIVE="netsurf evince"
LAZARO_XFCE="xorg-server xf86-input-libinput xinit eudev mesa-dri-gallium
	xfce4 elogind gvfs lightdm lightdm-gtk-greeter polkit-elogind
	xfce4-screensaver xfce4-terminal font-dejavu dbus dbus-x11
	$LAZARO_NAVEGADOR_LIVE"

# util-linux: Calamares (kpmcore) busca los discos con "lsblk --json" y
# usa blkid, blockdev y sfdisk; busybox no trae lsblk y sin él Calamares
# dice "There are no partitions to install on".
# ckbcomp: dibuja las teclas en la vista previa del teclado de Calamares.
# gparted (+ xhost, que su lanzador usa para abrir la ventana como root):
# editor de particiones para revisar o preparar discos antes de instalar.
# zenity: avisa si se intenta abrir GParted y el instalador a la vez.
# spice-vdagent: portapapeles compartido (copiar y pegar) y ajuste de
# pantalla al probar la ISO en Virt Manager/QEMU con SPICE.
# pciutils: lspci con la base de datos de nombres, para que
# lazaro-graficas sepa de qué generación es una NVIDIA.
# xf86-video-vesa: cuando la única gráfica es una NVIDIA antigua y queda
# en modo seguro (sin nouveau) y se arranca en modo BIOS, no hay ninguna
# pantalla para el controlador "modesetting" de Xorg: solo VESA sabe
# dibujar ahí (Compaq Presario CQ50, GeForce 8200M). Xorg lo usa solo
# si no hay otro.
# dialog: menús en modo texto de lazaro-instalar-texto, el instalador
# para cuando la sesión gráfica no abre.
# tar (GNU, 0,5 MB): lazaro-traducciones saca de los paquetes de
# traducción solo el idioma elegido en la Bienvenida; es el mismo tar que
# hace ese trabajo al compilar.
# Red más allá del wifi y el cable, en la live y en el sistema instalado
# (la lista del instalado está en live/usr/share/lazaro/paquetes-base):
# - modemmanager + networkmanager-wwan + usb-modeswitch: módems USB 3G/4G
#   ("pendrives de internet") y módems internos.
# - networkmanager-ppp y -adsl: PPPoE, usuario y contraseña directo a un
#   módem ADSL en modo puente.
# - networkmanager-bluetooth: internet del celular por Bluetooth.
# - usbmuxd: internet del iPhone por cable USB (Android no lo necesita).
# - zd1211-firmware (memorias wifi USB ZyDAS ZD1211) y bluez-firmware
#   (Bluetooth USB Broadcom BCM203x): no son parte de linux-firmware.
# En la live va solo lo liviano (LAZARO_RED_LIVE): con 2 GB de RAM la
# sesión live entera vive en la memoria y ModemManager con Bluetooth
# dejaba sin lugar al instalador (Calamares no abría). Los módems 3G/4G y
# el internet del celular por Bluetooth funcionan en el sistema instalado;
# para instalar con internet sirven el cable, el wifi o el celular por USB.
LAZARO_RED_LIVE="usb-modeswitch usb-modeswitch-udev networkmanager-ppp
	networkmanager-adsl usbmuxd usbmuxd-udev zd1211-firmware bluez-firmware"
LAZARO_RED_EXTRA="$LAZARO_RED_LIVE modemmanager modemmanager-openrc
	networkmanager-wwan networkmanager-bluetooth"

LAZARO_LIVE="alpine-base $LAZARO_XFCE util-linux e2fsprogs dosfstools ckbcomp
	networkmanager networkmanager-wifi networkmanager-cli network-manager-applet
	wpa_supplicant calamares doas musl-locales tzdata kbd-bkeymaps
	adwaita-icon-theme setxkbmap udev-init-scripts udev-init-scripts-openrc
	gparted xhost zenity spice-vdagent spice-vdagent-openrc pciutils
	py3-gobject3 gtk+3.0
	xf86-video-vesa dialog tar
	plymouth plymouth-drm plymouth-openrc-plugin
	$LAZARO_RED_LIVE"

# ISO de 32 bits: la live arranca solo con lo básico (LAZARO_LIVE_BASE:
# consola, red, discos e instalador en modo texto) y el servicio
# lazaro-escritorio carga el resto (LAZARO_LIVE_ESCRITORIO) cuando la
# memoria alcanza (1,5 GB o más) y ya está activa la memoria comprimida.
# Con 1 GB el escritorio de prueba no cabe en la RAM: así el equipo
# igual arranca y se instala con lazaro-instalar-texto.
LAZARO_LIVE_BASE="alpine-base eudev udev-init-scripts udev-init-scripts-openrc
	util-linux e2fsprogs dosfstools doas musl-locales tzdata kbd-bkeymaps
	networkmanager networkmanager-wifi networkmanager-cli wpa_supplicant
	dbus pciutils dialog tar
	plymouth plymouth-drm plymouth-openrc-plugin
	$LAZARO_RED_LIVE"
LAZARO_LIVE_ESCRITORIO=""
if [ "$LAZARO_ARCH" = x86 ]; then
	for _p in $LAZARO_LIVE; do
		case " $(echo $LAZARO_LIVE_BASE) " in
			*" $_p "*) ;;
			*) LAZARO_LIVE_ESCRITORIO="$LAZARO_LIVE_ESCRITORIO $_p" ;;
		esac
	done
	unset _p
fi

# Firmware de los demás adaptadores de red (wifi, cable, bluetooth, USB y
# PCMCIA) y lo que faltaba de Intel y AMD, que no venía en la ISO, para que el sistema instalado sin
# internet tenga red con cualquier tarjeta que Alpine reconozca. La sesión
# live ya traía todo el firmware (va en el modloop). Medido con Alpine
# 3.24: unos 150 MB (mrvl, de Marvell, es casi la mitad).
# Quedan fuera, a propósito: qcom (163 MB, equipos ARM con Qualcomm),
# mellanox (101 MB, switches de centro de datos) y dpaa2 (equipos ARM de
# NXP): ninguno es un adaptador de red de un PC o portátil x86.
# Wifi: ath6k ath11k ath12k atmel libertas mrvl (mwifiex) mwl8k mwlwifi
# rsi rtw89 ti-connectivity wfx; bluetooth: ar3k qca (también wifi);
# cable: 3com bnx2 bnx2x cxgb3 cxgb4 e100 kaweth (USB) liquidio
# netronome qed qlogic realtek slicoss sxg tehuti tigon vxge airoha;
# módems ADSL USB: ueagle-atm; tarjetas PCMCIA: cis ositech.
# Intel, AMD y NVIDIA quedan completos: intel, i915, nvidia, amdgpu,
# radeon y los microcódigos ya venían; se agregan xe (gráficas Intel
# nuevas), isci (discos SAS Intel), amd (procesadores AMD: SEV, PMF),
# amdnpu (NPU de los Ryzen AI) y amdtee (seguridad de AMD), todos
# pequeños (menos de 4 MB). También cirrus (sonido de portátiles, 2 MB).
# Los últimos, diminutos (menos de 1,5 MB juntos, revisión de drivers de
# red del 2026-11-04): acenic, adaptec, sun y myricom (tarjetas de cable
# antiguas o de servidor), microchip y aeonsemi (chips de cable), nxp
# (Bluetooth NXP) y atusb (radio USB 802.15.4).
# linux-firmware de Alpine va quitando firmware viejo (edge, nov. 2026,
# ya no trae acenic, myricom ni sun): lo que no exista en la versión que
# se compila se salta con un aviso, en vez de romper la compilación. Solo
# si apk puede consultar los repositorios (si no, va la lista entera).
_fw_revisar=no
apk search -q -x linux-firmware-none 2>/dev/null | grep -q . && _fw_revisar=si
LAZARO_FIRMWARE_RED=""
for _fw in ath6k ath11k ath12k atmel libertas mrvl mwl8k mwlwifi rsi rtw89 \
		ti-connectivity wfx ar3k qca 3com bnx2 bnx2x cxgb3 cxgb4 e100 \
		kaweth liquidio netronome qed qlogic realtek slicoss sxg tehuti \
		tigon vxge airoha ueagle-atm cis ositech xe isci amd amdnpu \
		amdtee cirrus acenic adaptec sun microchip myricom aeonsemi nxp \
		atusb; do
	if [ "$_fw_revisar" = si ] && ! apk search -q -x "linux-firmware-$_fw" 2>/dev/null | grep -q .; then
		echo "AVISO: no existe linux-firmware-$_fw en esta versión de Alpine; se omite." >&2
		continue
	fi
	LAZARO_FIRMWARE_RED="$LAZARO_FIRMWARE_RED linux-firmware-$_fw"
done
unset _fw _fw_revisar

# broadcom-wl (paquetes/broadcom-wl): driver wifi privativo para las
# Broadcom sin driver libre. lazaro-instalar lo instala solo si encuentra
# una; akms lo compila en el equipo. Para eso necesita las cabeceras del
# kernel y el compilador (linux-lts-dev y build-base, unos 120 MB en la
# ISO): solo caben en la Completa (LAZARO_COMPLETA). En la Ligera se
# descargan, así que con esas tarjetas hace falta internet al instalar
# (cable o el celular por USB).
LAZARO_BROADCOM="broadcom-wl-src akms"
# El paquete es solo de 64 bits.
[ "$LAZARO_ARCH" != x86 ] || LAZARO_BROADCOM=""

# Controladores de más hardware (lazaro-controladores los instala solo si
# el equipo los necesita; ver la revisión del 2026-11-04). En las dos
# ediciones lo liviano (unos 10 MB): escáneres, celulares y cámaras,
# tabletas Wacom, discos de Windows, temperatura, lectores de huellas y
# de tarjetas (DNI electrónico), sensores de giro de los 2 en 1,
# Thunderbolt, perfiles de sonido de portátiles nuevos y b43-fwcutter
# (firmware del wifi Broadcom b43, que se descarga con permiso).
LAZARO_HARDWARE="sane sane-airscan simple-scan gvfs-mtp gvfs-gphoto2 gvfs-afc
	xf86-input-wacom libwacom ntfs-3g exfatprogs mtools lm-sensors
	fprintd fprintd-pam pcsc-lite pcsc-lite-openrc ccid opensc
	iio-sensor-proxy iio-sensor-proxy-openrc bolt alsa-ucm-conf b43-fwcutter"
# Solo en la Completa, lo pesado (en la Ligera se descarga si hace falta):
# sonido Intel Smart Sound de portátiles nuevos (sof-firmware, 42 MB),
# impresoras HP, Epson, Brother, Samsung y otras (unos 120 MB), ahorro de
# batería (power-profiles-daemon, trae Python), actualizar firmware
# (fwupd) y braille con lector de pantalla (brltty, orca).
LAZARO_HARDWARE_COMPLETA="sof-firmware hplip epson-inkjet-printer-escpr
	gutenprint-cups brlaser splix power-profiles-daemon fwupd fwupd-openrc
	brltty orca"

# Lo que necesitan setup-disk y el sistema instalado, para instalar sin
# internet: el world del destino (live/usr/share/lazaro/paquetes-base,
# el mismo archivo que usa lazaro-instalar) más kernel, GRUB y firmware
# de portátiles comunes (setup-disk elige el firmware según el hardware;
# lo que no esté aquí se descarga si hay internet).
LAZARO_DESTINO="$(grep -v '^#' "${LAZARO_DIR:?}/live/usr/share/lazaro/paquetes-base")
	linux-lts mkinitfs grub grub-bios grub-efi efibootmgr sfdisk parted
	udev-init-scripts udev-init-scripts-openrc
	linux-firmware-none linux-firmware-other linux-firmware-intel
	linux-firmware-i915 linux-firmware-radeon linux-firmware-amdgpu
	linux-firmware-nvidia linux-firmware-ath9k_htc linux-firmware-ath10k
	linux-firmware-brcm linux-firmware-rtlwifi linux-firmware-rtw88
	linux-firmware-rtl_nic linux-firmware-rtl_bt linux-firmware-mediatek
	$LAZARO_FIRMWARE_RED
	intel-ucode amd-ucode
	$LAZARO_RED_EXTRA
	$LAZARO_BROADCOM
	$LAZARO_HARDWARE"

# Escritorios livianos completos en la ISO, para instalarlos sin
# internet como XFCE: lo que instala "setup-desktop" para cada uno
# (alpine-conf 3.22.0) más lo que desktop-postinstall.sh agrega en ese
# escritorio (applets de red y sonido, barra de Sway, agente de
# contraseñas). GNOME y Plasma no caben (más de 2 GB) y se descargan.
# Unos 240 MB en total.
LAZARO_ESCRITORIOS="
	mate-desktop-environment polkit mate-media mate-polkit
	lxqt-desktop lximage-qt obconf-qt pavucontrol-qt arandr sddm openbox
	udisks2 adwaita-qt oxygen lxqt-policykit xdg-desktop-portal-lxqt
	sway swaybg swayidle swaylockd foot grim i3status brightnessctl
	util-linux-login wl-clipboard wmenu xwayland waybar font-awesome fuzzel
	pavucontrol polkit-gnome greetd-gtkgreet seatd
	labwc adwaita-icon-theme network-manager-applet"

# 32 bits: solo XFCE (el de la live) y LXQt.
[ "$LAZARO_ARCH" != x86 ] || LAZARO_ESCRITORIOS="
	lxqt-desktop lximage-qt obconf-qt pavucontrol-qt arandr sddm openbox
	udisks2 adwaita-qt oxygen lxqt-policykit xdg-desktop-portal-lxqt
	adwaita-icon-theme network-manager-applet"

# Programas de "Software adicional" que vienen en la ISO (unos 325 MB):
# lazaro-instalar los instala desde el USB, sin internet, y
# desktop-postinstall.sh después los encuentra ya puestos. También van
# las tipografías que el script instala con cualquier escritorio.
# libreoffice-lang-es: solo el español; otro idioma se descarga.
# usbutils y xrandr: el script los pide siempre (revisión de hardware y
# resolución de la pantalla de inicio); si el wifi se corta durante la
# instalación, salen de la ISO.
# YouTube ligero (~18 MB): pipe-viewer-gtk, mpv y yt-dlp con QuickJS
# (yt-dlp-ejs-rt-quickjs evita que yt-dlp traiga Deno, 41 MB).
LAZARO_EXTRAS="fastfetch btop vlc vlc-qt libreoffice libreoffice-lang-es
	pipe-viewer pipe-viewer-gtk mpv yt-dlp yt-dlp-ejs-rt-quickjs
	flatpak font-liberation font-liberation-sans-narrow font-noto
	font-noto-emoji usbutils xrandr libcap-setcap"

# 32 bits: sin Flatpak (Flathub no publica aplicaciones de 32 bits). Van
# los dos navegadores: NetSurf se instala siempre y Firefox es una
# casilla de "Software adicional". Sin VLC: mpv ya reproduce video y
# música, y así la ISO entra en 2 GB.
[ "$LAZARO_ARCH" != x86 ] ||
	LAZARO_EXTRAS="$(echo $LAZARO_EXTRAS | sed 's/ flatpak / /; s/ vlc vlc-qt / /') netsurf firefox"

# Edición Completa (LAZARO_EDICION=completa): además, GNOME y Plasma tal
# como los instala setup-desktop (alpine-conf 3.22.0) y lo que les agrega
# desktop-postinstall.sh, todo el firmware (linux-firmware trae los 113
# subpaquetes) y las traducciones ("lang"). build.sh completa la lista con
# perfil/paquetes-completa.sh (todo lo que instala el script y lo que apk
# agrega solo, como las traducciones de cada programa) y la deja en
# $LAZARO_PAQUETES_COMPLETA. Las aplicaciones de Flathub van aparte, en la
# carpeta flatpak/ de la ISO (section_lazaro_flatpak).
LAZARO_COMPLETA="gnome gnome-apps-core gdm
	plasma-desktop-meta kde-applications-base sddm plasma-nm plasma-pa
	plasma-desktop-lang kdeplasma-addons-lang xdg-desktop-portal-kde
	seatd mesa-egl xwayland
	linux-firmware lang
	linux-lts-dev build-base
	$LAZARO_HARDWARE_COMPLETA"

profile_lazaro() {
	profile_standard
	title="Lázaro Linux"
	desc="Tu hardware aún tiene pulso.
		Sesión live con XFCE e instalador Calamares."
	profile_abbrev="lazaro"
	image_name="lazaro-linux"
	arch="x86_64 x86"
	kernel_addons=
	# console=ttyS0 primero y tty0 al final: la consola principal sigue
	# siendo la pantalla; el puerto serie solo sirve a las pruebas (QEMU).
	# rootflags=size=85%: la sesión live se instala en la RAM (tmpfs), y
	# Alpine solo le deja la mitad de la memoria. Con 4 GB o menos (más lo
	# que se queda la gráfica integrada) no alcanzaba: faltaban paquetes,
	# no se creaba el usuario y no arrancaba el escritorio. El límite no
	# reserva memoria: solo se ocupa lo que se usa.
	kernel_cmdline="console=ttyS0,115200 console=tty0 rootflags=size=85%"
	# nouveau no se carga solo en la live: lo carga lazaro-graficas
	# después de revisar la tarjeta, si es seguro.
	lazaro_nvidia="modprobe.blacklist=nouveau"
	# Pantalla de arranque con el pulso (Plymouth), salvo en el modo
	# gráfico seguro. Plymouth no dibuja en el puerto serie.
	lazaro_splash="splash plymouth.ignore-serial-consoles"
	syslinux_serial="0 115200"
	boot_addons="amd-ucode intel-ucode"
	initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
	apks="$apks $LAZARO_LIVE $LAZARO_DESTINO $LAZARO_EXTRAS $LAZARO_ESCRITORIOS"
	if [ "${LAZARO_EDICION:-ligera}" = completa ]; then
		title="Lázaro Linux Completa"
		desc="Tu hardware aún tiene pulso.
		Edición completa: se instala sin internet con cualquier escritorio."
		apks="$apks $(cat "${LAZARO_PAQUETES_COMPLETA:?falta la lista de la edición Completa}")"
		lazaro_edicion=" Completa"
		# Los objetos del repositorio de Flatpak tienen nombres de 68
		# letras: Joliet solo admite 64 sin esta opción (Linux lee los de
		# Rock Ridge, completos).
		iso_opts="$iso_opts -joliet-long"
	fi
	if [ "$LAZARO_ARCH" = x86 ]; then
		title="Lázaro Linux 32 bits"
		desc="Tu hardware aún tiene pulso.
		Para equipos de 32 bits: XFCE o LXQt."
		lazaro_edicion=" 32 bits"
		# Lo que instala desktop-postinstall.sh, para que la configuración
		# final no necesite internet (lista de build.sh).
		apks="$apks $(cat "${LAZARO_PAQUETES_COMPLETA:?falta la lista de paquetes de la ISO de 32 bits}")"
	fi
	grub_mod="$grub_mod serial terminal"
	apkovl="genapkovl-lazaro.sh"
	# genapkovl-lazaro.sh corre como proceso aparte: recibe la lista así.
	export LAZARO_WORLD="$LAZARO_LIVE"
	if [ "$LAZARO_ARCH" = x86 ]; then
		export LAZARO_WORLD="$LAZARO_LIVE_BASE"
		export LAZARO_WORLD_ESCRITORIO="$LAZARO_LIVE_ESCRITORIO"
	fi
	hostname="lazaro"
}

# Nombre del volumen y textos del menú de arranque. Van sin tildes
# porque GRUB y syslinux de la ISO no cargan una fuente con acentos.
gen_volid() {
	printf "%s" "LAZARO ${RELEASE%_rc*}" | cut -c1-32
}

syslinux_gen_config() {
	[ -z "$syslinux_serial" ] || echo "SERIAL $syslinux_serial"
	echo "SAY Lazaro Linux$lazaro_edicion - Tu hardware aun tiene pulso"
	echo "TIMEOUT ${syslinux_timeout:-30}"
	echo "PROMPT 1"
	echo "DEFAULT lazaro"
	cat <<- EOF

	LABEL lazaro
		MENU LABEL Lazaro Linux$lazaro_edicion (sesion live)
		KERNEL /boot/vmlinuz-lts
		INITRD /boot/amd-ucode.img,/boot/intel-ucode.img,/boot/initramfs-lts
		APPEND $initfs_cmdline $kernel_cmdline $lazaro_nvidia $lazaro_splash

	LABEL seguro
		MENU LABEL Lazaro Linux (modo grafico seguro)
		KERNEL /boot/vmlinuz-lts
		INITRD /boot/amd-ucode.img,/boot/intel-ucode.img,/boot/initramfs-lts
		APPEND $initfs_cmdline $kernel_cmdline $lazaro_nvidia nomodeset
	EOF
	[ "$LAZARO_ARCH" = x86 ] || return 0
	cat <<- EOF

	LABEL texto
		MENU LABEL Lazaro Linux (instalar en modo texto, poca memoria)
		KERNEL /boot/vmlinuz-lts
		INITRD /boot/amd-ucode.img,/boot/intel-ucode.img,/boot/initramfs-lts
		APPEND $initfs_cmdline $kernel_cmdline $lazaro_nvidia lazaro.escritorio=no
	EOF
}

grub_gen_config() {
	cat <<- EOF
	set timeout=5
	serial --unit=0 --speed=115200
	terminal_input console serial
	terminal_output console serial

	menuentry "Lazaro Linux$lazaro_edicion - Tu hardware aun tiene pulso" {
		linux	/boot/vmlinuz-lts $initfs_cmdline $kernel_cmdline $lazaro_nvidia $lazaro_splash
		initrd	/boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts
	}

	menuentry "Lazaro Linux (modo grafico seguro)" {
		linux	/boot/vmlinuz-lts $initfs_cmdline $kernel_cmdline $lazaro_nvidia nomodeset
		initrd	/boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts
	}
	EOF
	[ "$LAZARO_ARCH" = x86 ] || return 0
	cat <<- EOF

	menuentry "Lazaro Linux (instalar en modo texto, poca memoria)" {
		linux	/boot/vmlinuz-lts $initfs_cmdline $kernel_cmdline $lazaro_nvidia lazaro.escritorio=no
		initrd	/boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts
	}
	EOF
}

# Edición Completa: OnlyOffice y Brave de Flathub, con su runtime, en la
# carpeta flatpak/ de la ISO. La prepara el flujo de GitHub Actions (paso
# "Aplicaciones de Flathub para el USB") como un repositorio de Flatpak
# local; lazaro-instalar las instala desde ahí en el sistema nuevo. Solo
# si build.sh recibió la carpeta (LAZARO_FLATPAK_USB).
section_lazaro_flatpak() {
	[ "${LAZARO_EDICION:-ligera}" = completa ] || return 0
	[ -d "${LAZARO_FLATPAK_USB:-}/repo" ] || return 0
	build_section lazaro_flatpak $(cd "$LAZARO_FLATPAK_USB" && find . -type f | sort | checksum)
}

build_lazaro_flatpak() {
	mkdir -p "$DESTDIR/flatpak"
	cp -R "$LAZARO_FLATPAK_USB"/. "$DESTDIR/flatpak/"
}
