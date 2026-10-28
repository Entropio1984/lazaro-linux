#!/bin/sh
# Pruebas automáticas de la ISO en QEMU (las usa GitHub Actions, pero
# también sirven en cualquier Linux con qemu-system-x86_64, xorriso y
# socat; con OVMF para UEFI e ImageMagick para medir las capturas).
#
#   pruebas/qemu.sh live ISO bios|uefi [MEMORIA_MB]
#       Arranca la ISO como lo haría un usuario y espera a que Calamares
#       se abra en el escritorio. Guarda capturas de pantalla. MEMORIA_MB
#       (por omisión 4096): para probar equipos con poca RAM.
#
#   pruebas/qemu.sh instalar ISO bios|uefi ESCRITORIO con-red|sin-red
#       Instala sin interfaz (lazaro-instalar auto) en un disco virtual,
#       y luego arranca el disco y comprueba que el sistema instalado
#       inicia con su gestor de sesión.
#
# Resultados (registro del puerto serie y capturas) en pruebas/resultados/.
# Nunca toca discos reales: todo ocurre en archivos dentro de esa carpeta.

set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
RES="${RESULTADOS:-$DIR/resultados}"
mkdir -p "$RES"
# Los sockets UNIX no admiten rutas de más de 108 bytes, así que el del
# monitor de QEMU va en una carpeta temporal corta.
SOCK_DIR="$(mktemp -d /tmp/lzq.XXXXXX)"
trap 'rm -rf "$SOCK_DIR"' EXIT

uso() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0" >&2; exit 2; }

[ $# -ge 3 ] || uso
orden="$1"
[ -f "$2" ] || { echo "No existe la ISO: $2 (indica un solo archivo)" >&2; exit 2; }
ISO="$(realpath "$2")"
MODO="$3"
case "$MODO" in bios|uefi) ;; *) echo "Modo inválido: $MODO (usa bios o uefi)" >&2; uso ;; esac

KVM=""
[ -w /dev/kvm ] && KVM="-enable-kvm -cpu host"
MEM="${MEM:-4096}"

# Firmware UEFI para QEMU. Se busca una sola vez, aquí y no dentro de
# $(...): ahí el "exit" no detendría la prueba y QEMU arrancaría en BIOS.
ovmf() {
	for d in /usr/share/OVMF /usr/share/edk2/ovmf /usr/share/qemu; do
		for c in OVMF_CODE_4M.fd OVMF_CODE.fd; do
			if [ -f "$d/$c" ]; then
				OVMF_CODE="$d/$c"
				OVMF_VARS_ORIG="$d/$(echo "$c" | sed 's/CODE/VARS/')"
				return 0
			fi
		done
	done
	echo "No se encontró OVMF (firmware UEFI para QEMU)" >&2
	exit 1
}
[ "$MODO" != uefi ] || ovmf

# arrancar NOMBRE MEMORIA ARCHIVO_SERIE [OPCIONES DE QEMU...]
# Arranca QEMU en segundo plano con lo que comparten todas las pruebas
# (KVM, firmware, pantalla, puerto serie y monitor en
# $SOCK_DIR/NOMBRE.mon) y deja su PID en $pid.
arrancar() {
	a_nombre="$1"
	a_mem="$2"
	a_serie="$3"
	shift 3
	if [ "$MODO" = uefi ]; then
		# Las variables EFI de cada prueba, en su propio archivo.
		[ -f "$RES/$a_nombre-vars.fd" ] || cp "$OVMF_VARS_ORIG" "$RES/$a_nombre-vars.fd"
		set -- -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
			-drive "if=pflash,format=raw,file=$RES/$a_nombre-vars.fd" "$@"
	fi
	# shellcheck disable=SC2086
	qemu-system-x86_64 $KVM -m "$a_mem" -smp 2 "$@" \
		-vga std -display none \
		-serial "file:$a_serie" -monitor "unix:$SOCK_DIR/$a_nombre.mon,server,nowait" &
	pid=$!
}

captura() { # socket archivo
	printf 'screendump %s\n' "$2.ppm" | socat - "UNIX-CONNECT:$1" >/dev/null 2>&1 || true
	sleep 2
	if [ -f "$2.ppm" ] && command -v convert >/dev/null 2>&1; then
		convert "$2.ppm" "$2.png" && rm -f "$2.ppm"
	fi
}

# tramo ARCHIVO DESDE HASTA: muestra esa parte del registro (diagnósticos).
tramo() {
	sed -n "/$2/,/$3/p" "$1" >&2
}

# esperar ARCHIVO_SERIE PID SEGUNDOS TEXTO_OK [TEXTO_FALLO]
esperar() {
	t=0
	while [ "$t" -lt "$3" ]; do
		if grep -q "$4" "$1" 2>/dev/null; then return 0; fi
		if [ -n "${5:-}" ] && grep -q "$5" "$1" 2>/dev/null; then return 1; fi
		if grep -q 'initramfs emergency recovery shell' "$1" 2>/dev/null; then
			echo "El initramfs no encontró el sistema y abrió la consola de emergencia" >&2
			return 1
		fi
		kill -0 "$2" 2>/dev/null || { grep -q "$4" "$1" 2>/dev/null; return $?; }
		sleep 5
		t=$((t + 5))
	done
	echo "Tiempo agotado ($3 s) esperando '$4'" >&2
	return 1
}

terminar() { kill "$1" 2>/dev/null || true; sleep 2; kill -9 "$1" 2>/dev/null || true; }

prueba_live() {
	nombre="live-$MODO-${MEM}mb"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	disco="$RES/$nombre.qcow2"
	rm -f "$serie" "$mon" "$disco"
	# Disco vacío: Calamares tiene que verlo para dejar instalar.
	qemu-img create -q -f qcow2 "$disco" 20G
	arrancar "$nombre" "$MEM" "$serie" \
		-cdrom "$ISO" -boot d \
		-drive "file=$disco,if=virtio,format=qcow2" \
		-nic user,model=virtio-net-pci \
		-spice "unix=on,addr=$SOCK_DIR/$nombre.spice,disable-ticketing=on" \
		-device virtio-serial-pci -chardev spicevmc,id=vdagent,name=vdagent \
		-device virtserialport,chardev=vdagent,name=com.redhat.spice.0
	ok=0
	if ! esperar "$serie" "$pid" 900 LAZARO-CALAMARES-ABIERTO LAZARO-CALAMARES-NO-ABRIO; then
		captura "$mon" "$RES/$nombre-fallo"
		echo "FALLO: Calamares no se abrió en la sesión live ($MODO)." >&2
		ok=1
	elif esperar "$serie" "$pid" 180 LAZARO-DISCOS-OK LAZARO-DISCOS-FALLO; then
		captura "$mon" "$RES/$nombre-calamares"
		if ! esperar "$serie" "$pid" 30 LAZARO-MODULOS-OK LAZARO-MODULOS-FALLO; then
			echo "FALLO: Calamares no pudo cargar alguna de sus pantallas o pasos ($MODO)." >&2
			sed -n '/LAZARO-MODULOS-FALLO/,+6p' "$serie" >&2
			ok=1
		elif ! grep -q 'LAZARO-GRAFICAS decision=sin-nvidia' "$serie"; then
			# La revisión de gráficas (lazaro-graficas) tiene que haber
			# corrido; en QEMU no hay NVIDIA.
			echo "FALLO: la revisión de tarjetas gráficas no corrió o no decidió lo esperado ($MODO)." >&2
			grep 'LAZARO-GRAFICAS' "$serie" >&2 || true
			ok=1
		elif ! grep -q 'LAZARO-RECOMENDACION escritorio=xfce .*disco=21GB flatpak=no' "$serie"; then
			# 4 GB de RAM y disco de 20 GiB (qemu-img "20G" = 21 GB
			# decimales): XFCE, y Flatpak sin marcar por el disco pequeño.
			echo "FALLO: la recomendación del instalador no corrió o no recomendó lo esperado ($MODO)." >&2
			grep 'LAZARO-RECOMENDACION' "$serie" >&2 || true
			ok=1
		elif ! grep -q LAZARO-LIVE-LISTO "$serie" || grep -q 'No space left on device' "$serie"; then
			# La sesión live entera vive en la RAM: no debe quedarse sin
			# espacio al instalarse ni dejar de preparar su usuario.
			echo "FALLO: la sesión live no cupo en la memoria ($MEM MB) o no se preparó ($MODO)." >&2
			grep -e 'No space left' -e LAZARO-RAIZ "$serie" | head -n 10 >&2 || true
			ok=1
		elif ! grep -q LAZARO-DOAS-OK "$serie"; then
			echo "FALLO: en la sesión live, doas no da acceso de root al usuario lazaro ($MODO)." >&2
			ok=1
		elif ! grep -q LAZARO-SALVAPANTALLAS-NO "$serie"; then
			echo "FALLO: en la sesión live corre el salvapantallas, que apaga la pantalla durante la instalación ($MODO)." >&2
			ok=1
		elif ! grep -q LAZARO-ELOGIND-OK "$serie" || ! grep -q LAZARO-DPMS-OK "$serie"; then
			echo "FALLO: en la sesión live la pantalla todavía puede apagarse o el equipo suspenderse ($MODO)." >&2
			grep -A 8 -e LAZARO-ELOGIND- -e LAZARO-DPMS- "$serie" | head -n 20 >&2
			ok=1
		elif esperar "$serie" "$pid" 120 LAZARO-SPICE-OK LAZARO-SPICE-NO; then
			echo "OK: la sesión live arrancó ($MODO), Calamares se abrió, ve el disco y el portapapeles compartido funciona."
		else
			echo "FALLO: el agente del portapapeles compartido (spice-vdagent) no corre en la sesión live ($MODO)." >&2
			sed -n '/LAZARO-SPICE-NO/,$p' "$serie" | head -n 30 >&2
			ok=1
		fi
	else
		captura "$mon" "$RES/$nombre-fallo"
		echo "FALLO: Calamares se abrió pero no ve ningún disco ($MODO)." >&2
		ok=1
	fi
	terminar "$pid"
	rm -f "$disco"
	tail -n 400 "$serie" || true
	return $ok
}

prueba_instalar() {
	de="$1"
	red="$2"
	nombre="instalar-$MODO-$de-$red"
	disco="$RES/$nombre.qcow2"
	serie="$RES/$nombre-instalacion.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$disco" "$serie" "$mon" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G

	nic=user,model=virtio-net-pci
	[ "$red" = con-red ] || nic=none

	# Kernel e initramfs de la propia ISO, para poder pasar parámetros de
	# instalación desatendida sin tocar el menú de arranque.
	k="$RES/vmlinuz-lts"
	i="$RES/initramfs-lts"
	xorriso -osirrox on -indev "$ISO" \
		-extract /boot/vmlinuz-lts "$k" \
		-extract /boot/initramfs-lts "$i" >/dev/null 2>&1
	chmod u+w "$k" "$i"

	# Con OVMF y arranque directo del kernel, el CD por IDE no se detecta a
	# tiempo y el initramfs no encuentra la ISO; por virtio-scsi sí.
	# Las opciones del CD quedan en "$@" (de y red ya están guardados).
	mods="loop,squashfs,sd-mod,usb-storage"
	if [ "$MODO" = uefi ]; then
		set -- -device virtio-scsi-pci,id=scsi0 \
			-drive "id=cd0,if=none,media=cdrom,readonly=on,file=$ISO" \
			-device scsi-cd,drive=cd0,bus=scsi0.0
		mods="$mods,virtio_scsi,sr-mod"
	else
		set -- -cdrom "$ISO"
	fi

	echo "Instalando ($MODO, $de, $red)..."
	arrancar "$nombre" "$MEM" "$serie" \
		-kernel "$k" -initrd "$i" \
		-append "modules=$mods console=tty0 console=ttyS0,115200 lazaro.autoinstall=$de lazaro.disco=/dev/vda" \
		"$@" -drive "file=$disco,if=virtio,format=qcow2" -nic "$nic"
	if ! esperar "$serie" "$pid" 3600 LAZARO-AUTOINSTALL-OK LAZARO-AUTOINSTALL-FALLO; then
		captura "$mon" "$RES/$nombre-instalacion-fallo"
		terminar "$pid"
		echo "FALLO: la instalación desatendida no terminó bien." >&2
		tail -n 120 "$serie" >&2 || true
		return 1
	fi
	# Calamares muestra en su registro lo que lazaro-instalar escribe: debe
	# verse el avance por paquete mientras setup-desktop instala (sin
	# escritorio no hay ese paso: setup-disk no escribe una línea por
	# paquete).
	if [ "$de" != ninguno ] && ! grep -Eq '^\[lazaro\] \([0-9]+/[0-9]+\) Instalando [^[:space:]]' "$serie"; then
		terminar "$pid"
		echo "FALLO: el instalador no mostró el avance por paquete." >&2
		return 1
	fi
	# Los programas adicionales marcados (la prueba marca flatpak y
	# fastfetch) y las tipografías vienen en la ISO: se instalan desde el
	# USB, con o sin internet.
	if ! grep -q '^\[lazaro\] Programas adicionales instalados desde el USB' "$serie"; then
		terminar "$pid"
		echo "FALLO: los programas adicionales no se instalaron desde el USB." >&2
		grep -A 15 'Instalando desde el USB' "$serie" | head -n 30 >&2 || true
		return 1
	fi
	# Flatpak viene por defecto: con red debe quedar Flathub agregado.
	if [ "$red" = con-red ] && [ "$de" != ninguno ] && ! grep -q LAZARO-FLATPAK-OK "$serie"; then
		terminar "$pid"
		echo "FALLO: Flatpak/Flathub no quedó instalado." >&2
		sed -n '/LAZARO-FLATPAK-NO/,$p' "$serie" | head -n 60 >&2 || true
		return 1
	fi
	# La instalación apaga la máquina sola.
	t=0
	while kill -0 "$pid" 2>/dev/null && [ $t -lt 120 ]; do sleep 2; t=$((t + 2)); done
	terminar "$pid"

	echo "Arrancando el sistema instalado..."
	serie2="$RES/$nombre-arranque.log"
	rm -f "$serie2" "$mon" "$RES/$nombre-instalado.png" "$RES/$nombre-instalado.ppm" \
		"$RES/$nombre-pantalla-inicio.png" "$RES/$nombre-pantalla-inicio.ppm"
	# GNOME reinicia una vez en la prueba (GDM toma la resolución al
	# arrancar) y pide más memoria.
	mem2=2048
	espera2=600
	if [ "$de" = gnome ]; then
		mem2=3072
		espera2=1200
	fi
	arrancar "$nombre" "$mem2" "$serie2" \
		-drive "file=$disco,if=virtio,format=qcow2" -boot c -nic "$nic"
	ok=0
	# Qué resolución se revisa. Solo con red: sin red,
	# desktop-postinstall.sh corre recién en el primer arranque.
	#   dm   LightDM o SDDM: la pantalla de inicio tras cerrar la sesión
	#   gdm  GNOME: la pantalla de inicio tras reiniciar
	resolucion=""
	if [ "$red" = con-red ]; then
		case "$de" in
			xfce | mate | plasma) resolucion=dm ;;
			gnome) resolucion=gdm ;;
		esac
	fi
	if [ "$de" = gnome ]; then
		# Lo que haría la persona: pulsar Intro en "¿Mantener los
		# cambios?" de GNOME (el botón predeterminado es "Mantener").
		(
			esperar "$serie2" "$pid" "$espera2" LAZARO-CONFIRMAR >/dev/null 2>&1 || exit 0
			for _ in 1 2; do
				sleep 6
				printf 'sendkey ret\n' | socat - "UNIX-CONNECT:$mon" >/dev/null 2>&1 || true
			done
		) &
	fi
	if [ "$de" = sway ]; then
		(
			esperar "$serie2" "$pid" "$espera2" LAZARO-GTKGREET-LISTO >/dev/null 2>&1 || exit 0
			captura "$mon" "$RES/$nombre-pantalla-inicio"
		) &
	fi
	if esperar "$serie2" "$pid" "$espera2" LAZARO-PRUEBA-FIN; then
		captura "$mon" "$RES/$nombre-instalado"
		# Peso de las traducciones instaladas (solo informativo).
		sed -n '/LAZARO-LANG-TAMANO/,+10p' "$serie2" | tr -d '\r'
		tam=""
		if [ -f "$RES/$nombre-instalado.png" ]; then
			tam="$(identify -format '%wx%h' "$RES/$nombre-instalado.png" 2>/dev/null)" || tam=""
		fi
		if grep -q LAZARO-SERVICIOS-EN-SYSINIT "$serie2"; then
			echo "FALLO: hay servicios del escritorio en el nivel sysinit (arrancan antes de tiempo y cierran el pulso)." >&2
			grep LAZARO-SERVICIOS-EN-SYSINIT "$serie2" >&2
			ok=1
		elif grep -q LAZARO-PLYMOUTH-NO "$serie2"; then
			echo "FALLO: la pantalla de arranque (Plymouth) no cargó el tema del pulso." >&2
			tramo "$serie2" LAZARO-PLYMOUTH-NO '--- fin de plymouth'
			ok=1
		elif [ "$de" != ninguno ] && [ "$de" != gnome ] && ! grep -q LAZARO-PLYMOUTH-OK "$serie2" \
			&& ! { [ "$MODO" = uefi ] && grep -q LAZARO-PLYMOUTH-UEFI-SIN-VER "$serie2"; }; then
			# Con la pantalla del pulso, la prueba tiene que haber visto el
			# tema cargado (en UEFI se tolera que QEMU no llegue a mostrarlo).
			echo "FALLO: no se confirmó que la pantalla de arranque (Plymouth) cargara el tema del pulso." >&2
			grep LAZARO-PLYMOUTH "$serie2" >&2 || true
			ok=1
		elif grep -q LAZARO-VT-ESCONDIDA "$serie2"; then
			echo "FALLO: la pantalla de inicio quedó escondida detrás de la consola de texto." >&2
			grep LAZARO-VT-ESCONDIDA "$serie2" >&2
			ok=1
		elif grep -q LAZARO-VT-SIN-XORG "$serie2"; then
			echo "FALLO: LightDM o SDDM está instalado pero no se encontró su pantalla de inicio (Xorg) para ver si está al frente." >&2
			ok=1
		elif grep -q LAZARO-EXTRAS-NO "$serie2"; then
			echo "FALLO: no se instaló el programa adicional marcado (fastfetch)." >&2
			ok=1
		elif [ "$red" = con-red ] && ! grep -q LAZARO-EXTRAS-OK "$serie2"; then
			echo "FALLO: con internet no se confirmó la instalación del programa adicional marcado (fastfetch)." >&2
			ok=1
		elif grep -q LAZARO-HOME-AJENO "$serie2"; then
			echo "FALLO: falta la carpeta del usuario o tiene archivos de otro dueño (no podrá guardar su configuración)." >&2
			ok=1
		elif [ -n "$resolucion" ] && ! grep -q LAZARO-GUARDADO-OK "$serie2"; then
			if [ "$resolucion" = gdm ]; then
				echo "FALLO: GNOME no guardó la resolución que eligió el usuario (800x600)." >&2
			else
				echo "FALLO: la sesión del usuario no anotó la resolución que eligió (800x600)." >&2
			fi
			tramo "$serie2" '--- diagnóstico del guardado' '--- fin del diagnóstico'
			ok=1
		elif [ "$resolucion" = dm ] && ! grep -q LAZARO-PANTALLA-800x600 "$serie2"; then
			echo "FALLO: la pantalla de inicio no usó la resolución guardada del usuario (800x600)." >&2
			grep LAZARO-PANTALLA "$serie2" >&2 || true
			tramo "$serie2" '--- diagnóstico de la resolución' '--- fin del diagnóstico'
			ok=1
		elif [ "$resolucion" = gdm ] \
			&& { ! grep -q 'LAZARO-GDM-MODO 800x600' "$serie2" || [ "$tam" != 800x600 ]; }; then
			echo "FALLO: tras reiniciar, la pantalla de inicio de GNOME mide ${tam:-?}, no 800x600." >&2
			grep -E 'LAZARO-SALUDO|LAZARO-GDM-MODO' "$serie2" >&2 || true
			tramo "$serie2" '--- datos de GDM' '--- fin de los datos'
			ok=1
		elif [ "$red" = con-red ] && [ "$de" != ninguno ] && { ! grep -q 'LAZARO-IDIOMA-SESION ' "$serie2" \
			|| grep 'LAZARO-IDIOMA-SESION ' "$serie2" | tr -d '\r' | grep -qv ' es_CO\.UTF-8$'; }; then
			echo "FALLO: la sesión del usuario no quedó en el idioma elegido (es_CO.UTF-8)." >&2
			grep LAZARO-IDIOMA-SESION "$serie2" >&2 || echo "(no se encontró el panel de la sesión)" >&2
			sed -n '/LAZARO-IDIOMA-SIN-PANEL/,+60p' "$serie2" | grep -E '^(LAZARO-IDIOMA-SIN-PANEL|  )' >&2 || true
			ok=1
		elif [ "$de" = sway ] && ! grep -q LAZARO-GTKGREET-LISTO "$serie2"; then
			echo "FALLO: Sway no muestra su pantalla de inicio gráfica (gtkgreet)." >&2
			ok=1
		elif [ "$de" = sway ] && [ ! -s "$RES/$nombre-pantalla-inicio.png" ]; then
			echo "FALLO: no se pudo capturar la pantalla de inicio de Sway." >&2
			ok=1
		elif [ "$de" = sway ] && [ "$red" = con-red ] && ! grep -q LAZARO-GREETD-IDIOMA-OK "$serie2"; then
			echo "FALLO: la pantalla de inicio de Sway no quedó en el idioma elegido." >&2
			grep -E '^command|LAZARO-GTKGREET-LANG' "$serie2" >&2 || true
			ok=1
		elif [ "$de" = sway ] && ! grep -q 'LAZARO-SESION-GREETD-OK' "$serie2"; then
			echo "FALLO: desde la pantalla de inicio no se pudo entrar a Sway." >&2
			sed -n '/LAZARO-SESION-GREETD-NO/,$p' "$serie2" | head -n 35 >&2
			ok=1
		elif [ "$de" = sway ] && { ! grep -q 'LAZARO-SWAY-CORRE waybar' "$serie2" \
			|| ! grep -q 'LAZARO-SWAY-CORRE nm-applet' "$serie2" \
			|| ! grep -q 'LAZARO-SWAY-CORRE polkit-gnome-au' "$serie2" \
			|| ! grep -q 'LAZARO-SWAY-CORRE atajos' "$serie2"; }; then
			echo "FALLO: en Sway no arrancó la barra (waybar), el icono de wifi (nm-applet), el agente de contraseñas (polkit) o falta la lista de atajos." >&2
			grep LAZARO-SWAY-CORRE "$serie2" >&2 || true
			ok=1
		elif [ "$de" = ninguno ]; then
			if grep -Eq '(lightdm|sddm|gdm|greetd).*started|Starting (lightdm|sddm|gdm|greetd)|LAZARO-DM-ACTIVO' "$serie2"; then
				echo "FALLO: se eligió \"sin escritorio\" pero arrancó una pantalla de inicio gráfica." >&2
				ok=1
			else
				echo "OK: el sistema instalado arrancó en modo texto (sin escritorio)."
			fi
		elif grep -Eq '(lightdm|sddm|gdm|greetd).*started|status: started|LAZARO-DM-ACTIVO' "$serie2"; then
			echo "OK: el sistema instalado arrancó y su gestor de sesión está activo."
		else
			echo "FALLO: el sistema arrancó, pero el gestor de sesión no está activo." >&2
			ok=1
		fi
	else
		captura "$mon" "$RES/$nombre-arranque-fallo"
		echo "FALLO: el sistema instalado no terminó de arrancar." >&2
		ok=1
	fi
	terminar "$pid"
	tail -n 60 "$serie2" || true
	rm -f "$disco" "$k" "$i"
	return $ok
}

case "$orden" in
	live)
		[ $# -eq 3 ] || [ $# -eq 4 ] || uso
		[ $# -eq 3 ] || MEM="$4"
		prueba_live ;;
	instalar)
		[ $# -eq 5 ] || uso
		case "$5" in con-red|sin-red) ;; *) uso ;; esac
		prueba_instalar "$4" "$5" ;;
	*) uso ;;
esac
