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

# ISO de 32 bits: IceWM (el único escritorio: Julián, 2026-11-15) y
# "Sin escritorio"; sin Flatpak (Flathub no tiene aplicaciones de 32
# bits); NetSurf va siempre y Firefox pasa a ser una casilla. Se quitan de
# las pantallas de Calamares las opciones que no existen y se comprueba
# que quedó lo esperado. La sesión de prueba también es IceWM (live_icewm).
textos_32() {
	t3_cal="$tmp/etc/calamares/modules"
	awk '
		/^    - id:/ { ver = ($3 == "ninguno") }
		/^default:/ { print "default: icewm"; next }
		# IceWM va primero.
		/^items:/ {
			print
			print "    - id: icewm"
			print "      name: \"IceWM (recommended)\""
			print "      name[es]: \"IceWM (recomendado)\""
			print "      description: \"Light and modern: dark bar and menus like Windows 10, made for 1 GB of memory. Installs without internet.\""
			print "      description[es]: \"Liviano y moderno: barra y menús oscuros parecidos a Windows 10, pensado para equipos con 1 GB de memoria. Se instala sin internet desde el USB.\""
			print "      screenshot: \"escritorio-icewm.png\""
			next
		}
		/^    - id:/ || en_items { en_items = 1; if (ver) print; next }
		{ print }
	' "$t3_cal/packagechooser-escritorio.conf" > "$t3_cal/escritorio.nuevo"
	mv "$t3_cal/escritorio.nuevo" "$t3_cal/packagechooser-escritorio.conf"
	[ "$(grep -c '^    - id:' "$t3_cal/packagechooser-escritorio.conf")" = 2 ] ||
		{ echo "genapkovl-lazaro: la lista de escritorios de 32 bits no quedó con 2 opciones" >&2; exit 1; }
	# Software adicional: fuera el grupo de Flatpak (es el último) y VLC
	# (mpv ya reproduce video y música, y así entra en 2 GB); entra
	# Firefox, marcado, después de LibreOffice.
	awk '
		/^    - name: "Aplicaciones Flatpak/ { fuera = 1 }
		fuera { next }
		/^          - name: "VLC"/ { saltar = 4 }
		saltar > 0 { saltar--; next }
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
	! grep -q 'packages: \[ vlc \]' "$t3_cal/netinstall.conf" ||
		{ echo "genapkovl-lazaro: quedó la casilla de VLC en netinstall.conf" >&2; exit 1; }
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

# ISO de 32 bits: la sesión de prueba es IceWM (icewm-session), con el
# mismo tema "moderno" que deja desktop-postinstall.sh (se genera con sus
# funciones, así hay una sola copia) y el logo de Lázaro de fondo. Sin
# PCManFM ni lxsession, para que el escritorio y el instalador gráfico
# entren en 1 GB: el fondo lo pone IceWM y los programas de inicio
# (/etc/xdg/autostart: Bienvenida, red, aviso de gráfica) los abre
# /etc/icewm/startup, porque icewm-session no lo hace.
live_icewm() {
	li_dir="$tmp/etc/icewm"
	mkdir -p "$li_dir/themes"
	li_func="$(mktemp)"
	sed -n '/^ICEWM_TEMA=/p; /^icewm_tema()/,/^}/p; /^icewm_botones()/,/^}/p; /^icewm_boton_menu()/,/^}/p' \
		"$LAZARO_SCRIPT" > "$li_func"
	# shellcheck disable=SC1090
	( . "$li_func" && icewm_tema "$li_dir/themes" )
	rm -f "$li_func"
	[ -s "$li_dir/themes/moderno/default.theme" ] && [ -s "$li_dir/themes/moderno/closeA.xpm" ] ||
		{ echo "genapkovl-lazaro: no se pudo generar el tema de IceWM con desktop-postinstall.sh" >&2; exit 1; }

	cat > "$li_dir/preferences" <<-'EOF'
		# Sesión de prueba de Lázaro Linux (32 bits).
		Theme="moderno/default.theme"
		TaskBarAtTop=0
		TaskBarAutoHide=0
		TaskBarShowStartMenu=1
		TaskBarShowWindows=1
		TaskBarShowTray=1
		TaskBarShowClock=1
		TaskBarClockLeds=0
		TimeFormat="%H:%M"
		TaskBarShowShowDesktopButton=1
		TaskBarShowWorkspaces=0
		TaskBarShowWindowListMenu=0
		TaskBarShowCPUStatus=0
		TaskBarShowNetStatus=0
		TaskBarShowMEMStatus=0
		TaskBarShowMailboxStatus=0
		TaskBarShowCollapseButton=0
		TaskBarShowAPMStatus=0
		TaskBarShowAPMAuto=1
		TaskBarLaunchOnSingleClick=1
		ShowProgramsMenu=0
		ShowSettingsMenu=0
		ShowFocusModeMenu=0
		ShowThemesMenu=0
		ShowHelp=0
		ShowAbout=0
		ShowRun=0
		ShowWindowList=0
		ShowLogoutMenu=0
		ShowLogoutSubMenu=0
		MenuMouseTracking=1
		SubmenuMenuActivateDelay=150
		ClickToFocus=1
		RaiseOnFocus=1
		FocusOnAppRaise=1
		QuickSwitch=1
		EdgeSwitch=0
		OpaqueMove=1
		OpaqueResize=0
		SupportSemitransparency=0
		IconPath="/usr/share/icons/hicolor/64x64/apps:/usr/share/icons/hicolor/48x48/apps:/usr/share/pixmaps"
		MenuIconSize=16
		SmallIconSize=16
		LargeIconSize=32
		TitleFontNameXft="DejaVu Sans:size=10:bold"
		MenuFontNameXft="DejaVu Sans:size=10"
		NormalTaskBarFontNameXft="DejaVu Sans:size=10"
		ActiveTaskBarFontNameXft="DejaVu Sans:size=10"
		ToolButtonFontNameXft="DejaVu Sans:size=10"
		ClockFontNameXft="DejaVu Sans:size=10"
		ToolTipFontNameXft="DejaVu Sans:size=10"
		QuickSwitchFontNameXft="DejaVu Sans:size=10"
		DesktopBackgroundColor="#06223a"
		DesktopBackgroundImage="/usr/share/backgrounds/lazaro/lazaro-fondo.jpg"
		DesktopBackgroundScaled=1
	EOF

	cat > "$li_dir/toolbar" <<-'EOF'
		prog "Instalar Lázaro Linux" lazaro-bienvenida lazaro-abrir-instalador
		prog "Navegador" netsurf netsurf-gtk3
		prog "Terminal" lxterminal lxterminal
	EOF

	# El menú, en el idioma de la sesión (la Bienvenida puede cambiarlo).
	mkdir -p "$tmp/usr/share/lazaro"
	cat > "$tmp/usr/share/lazaro/icewm-menu" <<-'EOF'
		#!/bin/sh
		# Menú de IceWM de la sesión de prueba (32 bits), según el idioma.
		case "${LANG:-es}" in
		en*) t="Install Lázaro Linux|Welcome|Lázaro manual|Web browser|Terminal|Partition editor (GParted)|Restart|Shut down" ;;
		pt*) t="Instalar o Lázaro Linux|Boas-vindas|Manual do Lázaro|Navegador|Terminal|Editor de partições (GParted)|Reiniciar|Desligar" ;;
		*) t="Instalar Lázaro Linux|Bienvenida|Manual de Lázaro|Navegador|Terminal|Editor de particiones (GParted)|Reiniciar|Apagar" ;;
		esac
		IFS='|'
		# shellcheck disable=SC2086
		set -- $t
		echo "prog \"$1\" lazaro-bienvenida lazaro-abrir-instalador"
		echo "prog \"$2\" lazaro-bienvenida lazaro-bienvenida"
		command -v lazaro-manual >/dev/null 2>&1 && echo "prog \"$3\" help-browser lazaro-manual"
		echo "prog \"$4\" netsurf netsurf-gtk3"
		echo "prog \"$5\" lxterminal lxterminal"
		echo "prog \"$6\" gparted lazaro-abrir-gparted"
		echo "separator"
		echo "prog \"$7\" system-reboot doas -n /sbin/reboot"
		echo "prog \"$8\" system-shutdown doas -n /sbin/poweroff"
	EOF
	chmod 755 "$tmp/usr/share/lazaro/icewm-menu"
	echo "includeprog /usr/share/lazaro/icewm-menu" > "$li_dir/menu"

	cat > "$li_dir/startup" <<-'EOF'
		#!/bin/sh
		# Sesión de prueba (32 bits): icewm-session no abre los programas de
		# /etc/xdg/autostart (Bienvenida, red, aviso de gráfica); se abren
		# aquí. Se saltan los ocultos y los que son solo de otro escritorio.
		for f in /etc/xdg/autostart/*.desktop; do
			[ -f "$f" ] || continue
			grep -qi '^Hidden=true' "$f" && continue
			solo=$(sed -n 's/^OnlyShowIn=//p' "$f")
			case "$solo" in ''|*XFCE*|*ICEWM*) ;; *) continue ;; esac
			prueba=$(sed -n 's/^TryExec=//p' "$f")
			[ -z "$prueba" ] || command -v "$prueba" >/dev/null 2>&1 || continue
			orden=$(sed -n 's/^Exec=//p' "$f" | head -n 1 | sed 's/ %[a-zA-Z]//g')
			[ -n "$orden" ] || continue
			sh -c "$orden" >/dev/null 2>&1 &
		done
	EOF
	chmod 755 "$li_dir/startup"

	sed -i 's/^autologin-session=xfce$/autologin-session=icewm-session/' \
		"$tmp/etc/lightdm/lightdm.conf.d/50-lazaro-live.conf"
	grep -q '^autologin-session=icewm-session$' "$tmp/etc/lightdm/lightdm.conf.d/50-lazaro-live.conf" ||
		{ echo "genapkovl-lazaro: no se pudo poner IceWM en el inicio automático de LightDM" >&2; exit 1; }
}
[ "${ALPINE_ARCH:-x86_64}" != x86 ] || live_icewm

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
# 32 bits: el escritorio de la live lo carga después lazaro-escritorio,
# solo si la memoria alcanza.
if [ -n "${LAZARO_WORLD_ESCRITORIO:-}" ]; then
	mkdir -p "$tmp"/etc/lazaro
	printf '%s\n' $LAZARO_WORLD_ESCRITORIO > "$tmp"/etc/lazaro/world-escritorio
else
	rm -f "$tmp"/etc/init.d/lazaro-escritorio
fi

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
[ -z "${LAZARO_WORLD_ESCRITORIO:-}" ] || rc_add lazaro-escritorio boot
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
