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
#   pruebas/qemu.sh texto ISO bios|uefi
#       Arranca la ISO impidiendo que abra el escritorio y comprueba que
#       en la consola aparece el aviso del instalador en modo texto.
#
#   pruebas/qemu.sh poca ISO bios
#       Solo la ISO de 32 bits: con 1 GB de RAM no carga el escritorio de
#       prueba y muestra el aviso para instalar en modo texto.
#
# La ISO de 32 bits (*-x86.iso) se prueba en una máquina con procesador
# de 32 bits y 2 GB de RAM (MEM_32=1024 para probar con 1 GB), solo BIOS.
#
#   pruebas/qemu.sh instalar ISO bios|uefi ESCRITORIO con-red|sin-red
#       Instala sin interfaz (lazaro-instalar auto) en un disco virtual,
#       y luego arranca el disco y comprueba que el sistema instalado
#       inicia con su gestor de sesión. Con la ISO de la edición Completa
#       (nombre *-completa-*), también sin red se revisa la configuración
#       final y que OnlyOffice y Brave se instalaron desde el USB.
#   pruebas/qemu.sh instalar ISO bios|uefi ESCRITORIO con-red|sin-red broadcom
#       Igual, haciendo como si hubiera una wifi Broadcom que necesita
#       broadcom-wl: el driver debe quedar compilado en el disco.
#
#   pruebas/qemu.sh capturas ISO uefi
#       Capturas de pantalla para el Manual de Lázaro: el menú de
#       arranque, la sesión de prueba y las pantallas del instalador
#       (pulsando teclas como una persona), y después instala XFCE con
#       todo el software adicional y fotografía cada programa. Quedan en
#       pruebas/resultados/capturas/ (PNG, necesita ImageMagick).
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
QEMU=qemu-system-x86_64
# ISO de 32 bits (nombre *-x86.iso): una máquina con procesador de 32
# bits de verdad (Core Duo, 2006: no puede ejecutar nada de 64 bits) y
# 2 GB de RAM, lo que traen como mucho esos equipos. Solo BIOS.
BITS32=no
case "$ISO" in *-x86.iso)
	BITS32=si
	QEMU=qemu-system-i386
	KVM="-cpu coreduo"
	[ -w /dev/kvm ] && KVM="-enable-kvm -cpu coreduo"
	MEM="${MEM_32:-2048}"
	[ "$MODO" = bios ] || { echo "La ISO de 32 bits solo se prueba en modo BIOS." >&2; exit 2; }
	;;
esac

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
	"$QEMU" $KVM -m "$a_mem" -smp 2 "$@" \
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
		-device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
		-chardev null,id=lzprueba -device virtserialport,chardev=lzprueba,name=lazaro.prueba
	# El puerto lazaro.prueba le dice a la sesión live que abra también el
	# instalador: en un equipo real solo se abre la Bienvenida, y el
	# instalador se abre con su botón "Instalar Lázaro".
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
		elif ! grep -q LAZARO-BIENVENIDA-ABIERTA "$serie"; then
			echo "FALLO: la Bienvenida no se abrió al iniciar la sesión live ($MODO)." >&2
			ok=1
		elif ! grep -q '^LAZARO-CALAMARES-LANG es_' "$serie"; then
			# Calamares abre en español, como la sesión live.
			echo "FALLO: Calamares no abrió en español ($MODO)." >&2
			grep 'LAZARO-CALAMARES-LANG' "$serie" >&2 || true
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
		elif ! grep -q LAZARO-ZRAM-OK "$serie"; then
			# Memoria comprimida: sin ella, con 2 GB la sesión se caía.
			echo "FALLO: la sesión live no activó la memoria comprimida (zram) ($MODO)." >&2
			grep LAZARO-ZRAM "$serie" >&2 || true
			ok=1
		elif ! grep -q LAZARO-DOAS-OK "$serie"; then
			echo "FALLO: en la sesión live, doas no da acceso de root al usuario lazaro ($MODO)." >&2
			ok=1
		elif ! grep -q LAZARO-DOAS-LANG-OK "$serie"; then
			echo "FALLO: en la sesión live, doas no conserva el idioma (LANG) ($MODO)." >&2
			ok=1
		elif ! grep -q LAZARO-SALVAPANTALLAS-NO "$serie"; then
			echo "FALLO: en la sesión live corre el salvapantallas, que apaga la pantalla durante la instalación ($MODO)." >&2
			ok=1
		elif ! grep -q LAZARO-ELOGIND-OK "$serie" || ! grep -q LAZARO-DPMS-OK "$serie"; then
			echo "FALLO: en la sesión live la pantalla todavía puede apagarse o el equipo suspenderse ($MODO)." >&2
			grep -A 8 -e LAZARO-ELOGIND- -e LAZARO-DPMS- "$serie" | head -n 20 >&2
			ok=1
		elif ! grep -q 'LAZARO-IDIOMA-LIVE es_CO.UTF-8 traducciones=si' "$serie"; then
			# El escritorio de la live en español: LANG y las traducciones
			# que la ISO trae solo en español.
			echo "FALLO: la sesión live no arrancó en español ($MODO)." >&2
			grep 'LAZARO-IDIOMA-LIVE' "$serie" >&2 || true
			ok=1
		elif esperar "$serie" "$pid" 120 LAZARO-SPICE-OK LAZARO-SPICE-NO; then
			echo "OK: la sesión live arrancó en español ($MODO), Calamares se abrió, ve el disco y el portapapeles compartido funciona."
			grep -m1 -o 'LAZARO-ZRAM-OK.*' "$serie" | tr -d '\r' || true
			grep -m1 -o 'LAZARO-MEMORIA.*' "$serie" | tr -d '\r' || true
			# Cambio de idioma como el de la Bienvenida: descarga el
			# portugués de Brasil (la Completa lo trae en el USB), reinicia
			# la sesión y el escritorio y el instalador vuelven en portugués,
			# con el teclado brasileño.
			if ! esperar "$serie" "$pid" 900 LAZARO-IDIOMA-CAMBIO; then
				captura "$mon" "$RES/$nombre-idioma-fallo"
				echo "FALLO: no terminó el cambio de idioma de la sesión live ($MODO)." >&2
				grep -A 20 LAZARO-TRADUCCIONES-DESCARGA "$serie" >&2 || true
				ok=1
			elif ! grep -q 'LAZARO-IDIOMA-CAMBIO sesion=pt_BR.UTF-8 calamares=pt_BR.UTF-8 teclado=br traducciones=si' "$serie"; then
				captura "$mon" "$RES/$nombre-idioma-fallo"
				echo "FALLO: el cambio de idioma de la sesión live no quedó completo ($MODO)." >&2
				grep -A 20 -e LAZARO-TRADUCCIONES-DESCARGA -e LAZARO-IDIOMA-CAMBIO "$serie" >&2 || true
				ok=1
			elif ! esperar "$serie" "$pid" 600 LAZARO-IDIOMA-INGLES; then
				captura "$mon" "$RES/$nombre-idioma-fallo"
				echo "FALLO: no terminó el cambio al inglés de la sesión live ($MODO)." >&2
				ok=1
			elif ! grep -q 'LAZARO-IDIOMA-INGLES sesion=en_US.UTF-8 calamares=en_US.UTF-8' "$serie"; then
				captura "$mon" "$RES/$nombre-idioma-fallo"
				echo "FALLO: al cambiar al inglés, el escritorio o el instalador no volvieron en inglés ($MODO)." >&2
				grep -e LAZARO-IDIOMA-INGLES -e LAZARO-AVISO-TEXTO -e LAZARO-SESION-REINTENTO "$serie" >&2 || true
				ok=1
			elif grep -q -e LAZARO-AVISO-TEXTO -e LAZARO-SESION-REINTENTO "$serie"; then
				# Cambiar de idioma reinicia la sesión a propósito: aunque el
				# escritorio tarde en volver (la prueba al inglés simula un
				# equipo lento, 90 s), no debe aparecer el aviso del modo texto.
				captura "$mon" "$RES/$nombre-idioma-fallo"
				echo "FALLO: al cambiar de idioma, la live dio el escritorio por caído y mostró el aviso del modo texto ($MODO)." >&2
				grep -A 12 -e LAZARO-AVISO-TEXTO -e LAZARO-SESION-REINTENTO "$serie" >&2 || true
				ok=1
			else
				captura "$mon" "$RES/$nombre-ingles"
				echo "OK: cambio de idioma: $(grep -m1 -o 'LAZARO-TRADUCCIONES-DESCARGA.*' "$serie" | tr -d '\r')"
				echo "OK: cambio al inglés con un escritorio lento, sin el aviso del modo texto."
			fi
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
	tail -n 80 "$serie" || true
	return $ok
}

# Kernel e initramfs de la propia ISO en $k y $i, para pasar parámetros
# (instalación desatendida, pruebas) sin tocar el menú de arranque.
extraer_kernel() {
	k="$RES/vmlinuz-lts"
	i="$RES/initramfs-lts"
	xorriso -osirrox on -indev "$ISO" \
		-extract /boot/vmlinuz-lts "$k" \
		-extract /boot/initramfs-lts "$i" >/dev/null 2>&1
	chmod u+w "$k" "$i"
}

prueba_texto() {
	nombre="texto-$MODO"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$serie" "$mon" "$RES/$nombre-vars.fd"
	extraer_kernel
	mods="loop,squashfs,sd-mod,usb-storage"
	if [ "$MODO" = uefi ]; then
		set -- -device virtio-scsi-pci,id=scsi0 \
			-drive "id=cd0,if=none,media=cdrom,readonly=on,file=$ISO" \
			-device scsi-cd,drive=cd0,bus=scsi0.0
		mods="$mods,virtio_scsi,sr-mod"
	else
		set -- -cdrom "$ISO"
	fi
	arrancar "$nombre" "$MEM" "$serie" \
		-kernel "$k" -initrd "$i" \
		-append "modules=$mods console=tty0 console=ttyS0,115200 lazaro.prueba=sin-escritorio" \
		"$@" -nic none
	ok=0
	if ! esperar "$serie" "$pid" 900 LAZARO-AVISO-TEXTO; then
		echo "FALLO: sin escritorio, no apareció el aviso del instalador en modo texto ($MODO)." >&2
		ok=1
	elif ! grep -q LAZARO-DIALOG-OK "$serie"; then
		echo "FALLO: en la live falta dialog o lazaro-instalar-texto ($MODO)." >&2
		ok=1
	elif ! esperar "$serie" "$pid" 240 LAZARO-CONSOLA-OK LAZARO-CONSOLA-NO; then
		echo "FALLO: la consola de texto no entró sola como 'lazaro' ($MODO)." >&2
		ok=1
	else
		echo "OK: sin escritorio aparece el aviso del instalador en modo texto y la consola entra sola como 'lazaro' ($MODO)."
	fi
	sleep 5
	captura "$mon" "$RES/$nombre-aviso"
	terminar "$pid"
	[ "$ok" -eq 0 ] || tail -n 80 "$serie" >&2 || true
	rm -f "$k" "$i"
	return $ok
}

# ISO de 32 bits en un equipo con 1 GB de RAM: no debe cargar el
# escritorio de prueba (no cabe en la memoria) y tiene que mostrar el
# aviso para instalar en modo texto.
prueba_poca() {
	[ "$BITS32" = si ] || { echo "La prueba 'poca' es solo para la ISO de 32 bits." >&2; exit 2; }
	nombre="poca-$MODO"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$serie" "$mon"
	arrancar "$nombre" 1024 "$serie" -cdrom "$ISO" -boot d -nic none
	ok=0
	if ! esperar "$serie" "$pid" 900 'LAZARO-AVISO-TEXTO poca-memoria' LAZARO-ESCRITORIO-OK; then
		echo "FALLO: con 1 GB de RAM no apareció el aviso para instalar en modo texto." >&2
		ok=1
	elif ! grep -q 'LAZARO-ESCRITORIO-NO motivo=memoria' "$serie"; then
		echo "FALLO: con 1 GB de RAM la live intentó cargar el escritorio." >&2
		ok=1
	elif ! grep -q LAZARO-LIVE-LISTO "$serie" || grep -q 'No space left on device' "$serie"; then
		echo "FALLO: con 1 GB de RAM la sesión live básica no se preparó." >&2
		ok=1
	elif ! esperar "$serie" "$pid" 240 LAZARO-CONSOLA-OK LAZARO-CONSOLA-NO; then
		echo "FALLO: con 1 GB de RAM la consola de texto no entró sola como 'lazaro'." >&2
		ok=1
	else
		echo "OK: con 1 GB de RAM la live arranca sin escritorio, la consola entra sola como 'lazaro' y ofrece el instalador en modo texto."
		grep -m1 -o 'LAZARO-ESCRITORIO-NO.*' "$serie" | tr -d '\r' || true
		grep -m1 -o 'LAZARO-RAIZ.*' "$serie" | tr -d '\r' || true
	fi
	sleep 5
	captura "$mon" "$RES/$nombre-aviso"
	terminar "$pid"
	[ "$ok" -eq 0 ] || tail -n 80 "$serie" >&2 || true
	return $ok
}

prueba_instalar() {
	de="$1"
	red="$2"
	# broadcom: el instalador hace como si hubiera una wifi Broadcom que
	# necesita broadcom-wl y debe dejarlo compilado (QEMU no tiene una).
	broadcom="${3:-}"
	nombre="instalar-$MODO-$de-$red${broadcom:+-$broadcom}"
	disco="$RES/$nombre.qcow2"
	serie="$RES/$nombre-instalacion.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$disco" "$serie" "$mon" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G

	nic=user,model=virtio-net-pci
	[ "$red" = con-red ] || nic=none
	# configurado=si: desktop-postinstall.sh corre durante la instalación
	# (con red, o sin red en la edición Completa, que trae todo).
	completa=no
	case "$(basename "$ISO")" in *-completa-*) completa=si ;; esac
	configurado=no
	# todo_en_iso: la configuración final no necesita internet (edición
	# Completa y la de 32 bits).
	todo_en_iso="$completa"
	[ "$BITS32" = no ] || todo_en_iso=si
	{ [ "$red" = con-red ] || [ "$todo_en_iso" = si ]; } && configurado=si
	# con_tienda: el escritorio queda con tienda de aplicaciones (LXQt de
	# 32 bits no: Discover no va en esa ISO).
	con_tienda=si
	[ "$de" != ninguno ] || con_tienda=no
	{ [ "$BITS32" = si ] && [ "$de" = lxqt ]; } && con_tienda=no

	extraer_kernel

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
		-append "modules=$mods console=tty0 console=ttyS0,115200 lazaro.autoinstall=$de lazaro.disco=/dev/vda lazaro.controladores=huellas,tarjetas${broadcom:+ lazaro.broadcom=forzar}" \
		"$@" -drive "file=$disco,if=virtio,format=qcow2" -nic "$nic"
	if ! esperar "$serie" "$pid" 3600 LAZARO-AUTOINSTALL-OK LAZARO-AUTOINSTALL-FALLO; then
		captura "$mon" "$RES/$nombre-instalacion-fallo"
		terminar "$pid"
		echo "FALLO: la instalación desatendida no terminó bien." >&2
		tail -n 120 "$serie" >&2 || true
		return 1
	fi
	if [ -n "$broadcom" ] && ! grep -q LAZARO-BROADCOM-OK "$serie"; then
		terminar "$pid"
		echo "FALLO: broadcom-wl no quedó compilado en el sistema instalado." >&2
		sed -n '/LAZARO-BROADCOM-NO/,+45p' "$serie" | head -n 60 >&2 || true
		grep -iE 'broadcom|akms' "$serie" | tail -n 30 >&2 || true
		return 1
	fi
	[ -z "$broadcom" ] || echo "OK: broadcom-wl compilado ($(grep -m1 -o 'LAZARO-BROADCOM-OK.*' "$serie"))."
	# lazaro-controladores: la prueba simula un lector de huellas y uno de
	# tarjetas (lazaro.controladores=...); sus paquetes vienen en la ISO,
	# así que se instalan también sin internet. Si el escritorio ya los
	# trajo (Plasma trae fprintd), no aparecen en la lista de lo que falta.
	faltan="$(grep -m1 -o 'LAZARO-CONTROLADORES-FALTAN.*' "$serie" || true)"
	for c in huellas tarjetas; do
		if [ -z "$faltan" ] || grep -q "LAZARO-CONTROLADOR-NO $c" "$serie" \
			|| { case " $faltan " in *" $c "*) true ;; *) false ;; esac \
				&& ! grep -q "LAZARO-CONTROLADOR-OK $c" "$serie"; }; then
			terminar "$pid"
			echo "FALLO: lazaro-controladores no instaló '$c'." >&2
			grep -E 'LAZARO-CONTROLADOR|[Cc]ontroladores' "$serie" | tail -n 20 >&2 || true
			return 1
		fi
	done
	echo "OK: controladores: ${faltan#LAZARO-CONTROLADORES-FALTAN }"
	# lazaro-afinador: aplica lo recomendado al instalar; con escritorio,
	# eso incluye preempt=full en el menú de arranque.
	afinador="$(grep -m1 -o 'LAZARO-AFINADOR-OK.*' "$serie" || true)"
	if [ -z "$afinador" ] || { [ "$de" != ninguno ] && ! printf '%s' "$afinador" | grep -q 'preempt=full'; }; then
		terminar "$pid"
		echo "FALLO: el afinador no aplicó sus ajustes al instalar (${afinador:-sin línea LAZARO-AFINADOR-OK})." >&2
		grep -iE 'afinador' "$serie" | tail -n 20 >&2 || true
		return 1
	fi
	echo "OK: afinador: ${afinador#LAZARO-AFINADOR-OK}"
	# lazaro-repositorio: el sistema queda listo para que las herramientas
	# de Lázaro se actualicen solas.
	if [ "$BITS32" = si ] && grep -q 'LAZARO-REPOSITORIO-32-NO' "$serie"; then
		echo "OK: 32 bits, sin repositorio de Lázaro (todavía no existe para 32 bits)"
	elif ! grep -q 'LAZARO-REPOSITORIO-PREPARADO' "$serie"; then
		terminar "$pid"
		echo "FALLO: no se preparó el repositorio de Lázaro al instalar." >&2
		grep -iE 'repositorio' "$serie" | tail -n 20 >&2 || true
		return 1
	fi
	[ "$BITS32" = si ] || echo "OK: repositorio de Lázaro preparado"
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
	# (No en 32 bits: Flathub no tiene aplicaciones de 32 bits.)
	if [ "$BITS32" = no ] && [ "$red" = con-red ] && [ "$de" != ninguno ] && ! grep -q LAZARO-FLATPAK-OK "$serie"; then
		terminar "$pid"
		echo "FALLO: Flatpak/Flathub no quedó instalado." >&2
		sed -n '/LAZARO-FLATPAK-NO/,$p' "$serie" | head -n 60 >&2 || true
		return 1
	fi
	if [ "$todo_en_iso" = si ] && [ "$de" != ninguno ]; then
		if ! grep -q '^\[lazaro\] desktop-postinstall.sh terminó bien' "$serie"; then
			terminar "$pid"
			echo "FALLO: en la edición Completa y en la de 32 bits la configuración final debe terminar durante la instalación (también sin red)." >&2
			grep -E 'desktop-postinstall|ERROR|Aviso' "$serie" | tail -n 30 >&2 || true
			return 1
		fi
	fi
	if [ "$completa" = si ] && [ "$de" != ninguno ]; then
		if ! grep -q 'LAZARO-FLATPAK-USB-OK org.onlyoffice.desktopeditors' "$serie" \
			|| ! grep -q 'LAZARO-FLATPAK-USB-OK com.brave.Browser' "$serie" \
			|| ! grep -q LAZARO-FLATHUB-ORIGEN-OK "$serie"; then
			terminar "$pid"
			echo "FALLO: OnlyOffice y Brave no quedaron instalados desde el USB con Flathub como origen." >&2
			sed -n '/LAZARO-FLATPAK-USB-NO\|LAZARO-FLATHUB-ORIGEN-NO/,+30p' "$serie" | head -n 80 >&2 || true
			grep -E 'LAZARO-FLATPAK-USB|LAZARO-FLATHUB-ORIGEN' "$serie" >&2 || true
			return 1
		fi
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
	# 32 bits con MEM_32: el sistema instalado arranca con esa misma
	# memoria (la prueba del equipo de 1 GB).
	[ "$BITS32" = no ] || [ -z "${MEM_32:-}" ] || mem2="$MEM_32"
	arrancar "$nombre" "$mem2" "$serie2" \
		-drive "file=$disco,if=virtio,format=qcow2" -boot c -nic "$nic"
	ok=0
	# Qué resolución se revisa. Solo con red: sin red,
	# desktop-postinstall.sh corre recién en el primer arranque.
	#   dm   LightDM o SDDM: la pantalla de inicio tras cerrar la sesión
	#   gdm  GNOME: la pantalla de inicio tras reiniciar
	resolucion=""
	if [ "$configurado" = si ]; then
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
		elif [ "$configurado" = si ] && ! grep -q LAZARO-EXTRAS-OK "$serie2"; then
			echo "FALLO: con internet no se confirmó la instalación del programa adicional marcado (fastfetch)." >&2
			ok=1
		elif grep -q LAZARO-YOUTUBE-NO "$serie2"; then
			echo "FALLO: YouTube ligero quedó incompleto:" >&2
			grep LAZARO-YOUTUBE-NO "$serie2" >&2
			ok=1
		elif [ "$de" != ninguno ] && ! grep -q LAZARO-YOUTUBE-OK "$serie2"; then
			echo "FALLO: no se confirmó YouTube ligero (Pipe Viewer + mpv + yt-dlp con QuickJS)." >&2
			ok=1
		elif ! grep -q 'LAZARO-AFINADOR-ARRANQUE .*ttl=1000' "$serie2" \
			|| { [ "$BITS32" = no ] && [ "$de" != ninguno ] && ! grep -q 'LAZARO-AFINADOR-ARRANQUE .*Dynamic Preempt: full' "$serie2"; }; then
			echo "FALLO: el sistema instalado no arrancó con los ajustes del afinador." >&2
			grep LAZARO-AFINADOR "$serie2" >&2 || true
			ok=1
		elif grep -Eq 'LAZARO-TIENDA-NO.*(servicio|tarea)' "$serie2" ||
			{ [ "$red" = con-red ] && [ "$con_tienda" = si ] && ! grep -q LAZARO-TIENDA-OK "$serie2"; } ||
			{ [ "$configurado" = si ] && [ "$con_tienda" = si ] && ! grep -q LAZARO-TIENDA "$serie2"; }; then
			# Sin internet la lista de programas no se puede descargar: ahí
			# solo se exigen los servicios y la tarea que la descargará
			# (si la configuración final ya corrió, como en la Completa).
			# LXQt de 32 bits no tiene tienda: el script le pone Discover,
			# que trae cientos de paquetes de KDE y no va en esa ISO.
			echo "FALLO: la tienda de aplicaciones no quedó lista (servicio de Alpine o lista de programas para instalar)." >&2
			grep -A 5 LAZARO-TIENDA "$serie2" >&2 || true
			ok=1
		elif ! grep -q LAZARO-MANUAL-OK "$serie2"; then
			echo "FALLO: el Manual de Lázaro (PDF y acceso en el menú) no quedó en el sistema instalado (en una compilación local, compílalo antes con manual/compilar.sh)." >&2
			ok=1
		elif ! grep -q LAZARO-DIAGNOSTICO-OK "$serie2"; then
			echo "FALLO: el comando lazaro-diagnostico no dejó su informe en el sistema instalado." >&2
			grep LAZARO-DIAGNOSTICO "$serie2" >&2 || true
			ok=1
		elif grep -q LAZARO-BIENVENIDA-NO "$serie2" ||
			{ [ "$de" != ninguno ] && ! grep -q LAZARO-BIENVENIDA-OK "$serie2"; }; then
			echo "FALLO: la Bienvenida no quedó lista en el sistema instalado (programa, funciones o GTK para Python)." >&2
			grep LAZARO-BIENVENIDA "$serie2" >&2 || true
			ok=1
		elif ! grep -q LAZARO-ARREGLOS-OK "$serie2"; then
			echo "FALLO: las mejoras para equipos instalados (lazaro-arreglos) no quedaron anotadas como hechas, o falta lazaro-actualizar-raiz." >&2
			grep LAZARO-ARREGLOS "$serie2" >&2 || true
			ok=1
		elif grep -q LAZARO-BTOP-GPU-NO "$serie2"; then
			echo "FALLO: btop quedó sin el permiso para medir la GPU sin doas:" >&2
			grep LAZARO-BTOP-GPU-NO "$serie2" >&2
			ok=1
		elif ! grep -q LAZARO-DOAS-OK "$serie2"; then
			echo "FALLO: la regla de doas del sistema instalado no es válida o no conserva el idioma." >&2
			grep LAZARO-DOAS "$serie2" >&2 || true
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
		elif [ "$configurado" = si ] && [ "$de" != ninguno ] && { ! grep -q 'LAZARO-IDIOMA-SESION ' "$serie2" \
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
		elif [ "$de" = sway ] && [ "$configurado" = si ] && ! grep -q LAZARO-GREETD-IDIOMA-OK "$serie2"; then
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

# --- Capturas para el manual ---------------------------------------------
# tecla SOCKET TECLA...: pulsa teclas en la máquina (sendkey de QEMU).
tecla() {
	t_mon="$1"; shift
	for t_k in "$@"; do
		printf 'sendkey %s\n' "$t_k" | socat - "UNIX-CONNECT:$t_mon" >/dev/null 2>&1 || true
		sleep 1
	done
}

prueba_capturas() {
	CAP="$RES/capturas"
	mkdir -p "$CAP/otras"
	ok=0

	# 1. Sesión de prueba: menú de arranque y la Bienvenida, como la ve
	# cualquiera (sin el puerto lazaro.prueba, el instalador no se abre
	# solo).
	nombre="capturas-live"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	disco="$RES/$nombre.qcow2"
	rm -f "$serie" "$mon" "$disco" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G
	# El puerto lazaro.capturas le pide a la sesión que abra después la
	# ventana de Idioma y teclado.
	arrancar "$nombre" "$MEM" "$serie" -cdrom "$ISO" -boot d \
		-drive "file=$disco,if=virtio,format=qcow2" -nic user,model=virtio-net-pci \
		-device virtio-serial-pci \
		-chardev null,id=lzcapturas -device virtserialport,chardev=lzcapturas,name=lazaro.capturas
	# El menú de arranque se elige solo a los 5 s. La flecha arriba (ya
	# está en la primera opción) detiene la cuenta sin cambiar nada: el
	# menú queda quieto para la foto y Enter sigue el arranque normal.
	for n in 1 2 3 4 5 6 7 8; do
		tecla "$mon" up
		captura "$mon" "$CAP/otras/menu-arranque-$n"
	done
	cp "$CAP/otras/menu-arranque-8.png" "$CAP/menu-arranque.png" 2>/dev/null || true
	tecla "$mon" ret
	if esperar "$serie" "$pid" 900 LAZARO-LIVE-LISTO LAZARO-LIVE-NO-LISTO; then
		# El escritorio y la Bienvenida tardan en abrir después.
		sleep 120
		captura "$mon" "$CAP/sesion-prueba"
		if esperar "$serie" "$pid" 400 LAZARO-CAPTURA-IDIOMA; then
			captura "$mon" "$CAP/idioma"
		else
			echo "AVISO: no se abrió la ventana de Idioma y teclado para su captura." >&2
		fi
	else
		captura "$mon" "$CAP/otras/live-fallo"
		echo "FALLO: la sesión de prueba no arrancó." >&2
		ok=1
	fi
	terminar "$pid"
	rm -f "$disco"

	# 2. El instalador, abierto por el puerto lazaro.prueba como en las
	# pruebas, recorrido con el botón Siguiente (Alt+S).
	nombre="capturas-instalador"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	disco="$RES/$nombre.qcow2"
	rm -f "$serie" "$mon" "$disco" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G
	arrancar "$nombre" "$MEM" "$serie" -cdrom "$ISO" -boot d \
		-drive "file=$disco,if=virtio,format=qcow2" -nic user,model=virtio-net-pci \
		-device virtio-serial-pci \
		-chardev null,id=lzprueba -device virtserialport,chardev=lzprueba,name=lazaro.prueba
	if esperar "$serie" "$pid" 900 LAZARO-CALAMARES-ABIERTO LAZARO-CALAMARES-NO-ABRIO; then
		sleep 40
		captura "$mon" "$CAP/instalador-bienvenida"
		for p in instalador-ubicacion instalador-teclado instalador-escritorio instalador-software instalador-disco; do
			tecla "$mon" alt-s
			sleep 6
			captura "$mon" "$CAP/$p"
		done
	else
		captura "$mon" "$CAP/otras/instalador-fallo"
		echo "FALLO: Calamares no se abrió en la sesión de prueba." >&2
		ok=1
	fi
	terminar "$pid"
	rm -f "$disco"

	# 3. Sistema instalado con XFCE: cada programa.
	nombre="capturas-instalado"
	disco="$RES/$nombre.qcow2"
	serie="$RES/$nombre-instalacion.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$disco" "$serie" "$mon" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G
	extraer_kernel
	mods="loop,squashfs,sd-mod,usb-storage"
	if [ "$MODO" = uefi ]; then
		set -- -device virtio-scsi-pci,id=scsi0 \
			-drive "id=cd0,if=none,media=cdrom,readonly=on,file=$ISO" \
			-device scsi-cd,drive=cd0,bus=scsi0.0
		mods="$mods,virtio_scsi,sr-mod"
	else
		set -- -cdrom "$ISO"
	fi
	echo "Instalando XFCE para las capturas..."
	arrancar "$nombre" "$MEM" "$serie" \
		-kernel "$k" -initrd "$i" \
		-append "modules=$mods console=tty0 console=ttyS0,115200 lazaro.autoinstall=xfce lazaro.disco=/dev/vda lazaro.capturas=si" \
		"$@" -drive "file=$disco,if=virtio,format=qcow2" -nic user,model=virtio-net-pci
	if ! esperar "$serie" "$pid" 3600 LAZARO-AUTOINSTALL-OK LAZARO-AUTOINSTALL-FALLO; then
		captura "$mon" "$CAP/otras/instalacion-fallo"
		terminar "$pid"
		tail -n 120 "$serie" >&2 || true
		echo "FALLO: la instalación para las capturas no terminó." >&2
		return 1
	fi
	t=0
	while kill -0 "$pid" 2>/dev/null && [ $t -lt 120 ]; do sleep 2; t=$((t + 2)); done
	terminar "$pid"
	rm -f "$k" "$i"

	serie="$RES/$nombre-arranque.log"
	rm -f "$serie" "$mon"
	arrancar "$nombre" 4096 "$serie" \
		-drive "file=$disco,if=virtio,format=qcow2" -boot c -nic user,model=virtio-net-pci
	# El sistema avisa "LAZARO-CAPTURA nombre" con cada programa abierto.
	hechas=""
	t=0
	while [ $t -lt 2400 ] && kill -0 "$pid" 2>/dev/null; do
		# "LAZARO-CAPTURA nombre esc": antes de la foto, Esc cierra el
		# aviso de primer uso (LibreOffice, VLC).
		for c in $(sed -n 's/^LAZARO-CAPTURA \([a-z0-9-]*\)\( esc\)\{0,1\}.*/\1\2/p' "$serie" 2>/dev/null | tr -d '\r' | tr ' ' ':'); do
			esc="${c#*:}"; c="${c%%:*}"
			case " $hechas " in *" $c "*) continue ;; esac
			if [ "$esc" = esc ]; then
				tecla "$mon" esc
				sleep 3
			fi
			captura "$mon" "$CAP/$c"
			tecla "$mon" esc
			hechas="$hechas $c"
			echo "Captura: $c"
		done
		grep -q 'LAZARO-CAPTURAS-FIN\|LAZARO-CAPTURAS-SIN-SESION' "$serie" 2>/dev/null && break
		sleep 2
		t=$((t + 2))
	done
	grep 'LAZARO-CAPTURA-FALTA' "$serie" >&2 || true
	# Registro de las ventanas del Diagnóstico (por qué no abrirían).
	grep 'LAZARO-DIAGNOSTICO-VENTANA' "$serie" | tr '|' '\n' >&2 || true
	if ! grep -q LAZARO-CAPTURAS-FIN "$serie"; then
		captura "$mon" "$CAP/otras/instalado-fallo"
		echo "FALLO: el sistema instalado no terminó las capturas." >&2
		tail -n 60 "$serie" >&2 || true
		ok=1
	fi
	terminar "$pid"
	rm -f "$disco"
	echo "Capturas en $CAP:"
	ls -l "$CAP"
	return $ok
}

case "$orden" in
	live)
		[ $# -eq 3 ] || [ $# -eq 4 ] || uso
		[ $# -eq 3 ] || MEM="$4"
		prueba_live ;;
	texto)
		[ $# -eq 3 ] || uso
		prueba_texto ;;
	poca)
		[ $# -eq 3 ] || uso
		prueba_poca ;;
	instalar)
		[ $# -eq 5 ] || [ $# -eq 6 ] || uso
		case "$5" in con-red|sin-red) ;; *) uso ;; esac
		case "${6:-}" in "" | broadcom) ;; *) uso ;; esac
		prueba_instalar "$4" "$5" "${6:-}" ;;
	capturas)
		[ $# -eq 3 ] || uso
		prueba_capturas ;;
	*) uso ;;
esac
