#!/bin/sh
# Titulo: LXQt: la tecla Imprimir Pantalla saca capturas (ScreenGrab) y los ajustes del salvapantallas ya no piden paquetes
#
# LXQt trae la tecla Imprimir Pantalla configurada para ScreenGrab, pero
# no el programa, y la ventana de ajustes de XScreenSaver avisaba "the
# xscreensaver-gl* packages are required" (Completa con LXQt, 23 de
# noviembre de 2026). Copia de install_daily_apps de
# desktop-postinstall.sh desde esa fecha: screengrab y
# xscreensaver-gl-extras, y a quien todavía no tiene ~/.xscreensaver se
# le deja la pantalla en negro (sin animaciones que gasten procesador).
# A quien ya lo tiene no se le toca: es su elección.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

# Sin LXQt no hace falta; si la persona lo instala después, se vuelve a
# mirar.
instalado lxqt-desktop || instalado lxqt-session || exit 11

faltan=""
instalado screengrab || faltan="screengrab"
instalado xscreensaver-gl-extras || faltan="$faltan xscreensaver-gl-extras"
if [ -n "$faltan" ]; then
	# shellcheck disable=SC2086
	apk add -q $faltan || exit 1
fi

hizo=""
[ -z "$faltan" ] || hizo=si
for base in "$R/etc/skel" $(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home\// { print $6 }' "$R/etc/passwd" 2>/dev/null); do
	case "$base" in /home/*) base="$R$base" ;; esac
	[ -d "$base" ] || continue
	# Ya existe (aunque sea un enlace roto): es de la persona, no se toca.
	{ [ -e "$base/.xscreensaver" ] || [ -L "$base/.xscreensaver" ]; } && continue
	# A un archivo nuevo y después a su lugar sin pisar nada (mv -n): así
	# nunca se escribe, como root, a través de un enlace.
	xs="$(mktemp "$base/.xscreensaver.XXXXXX")" || exit 1
	cat > "$xs" <<'XSCREENSAVER' || { rm -f "$xs"; exit 1; }
# Lazaro Linux: solo lo que cambia; lo demas lo pone XScreenSaver.
# Pantalla en negro (sin animaciones que gasten procesador) y, en la
# lista, solo las animaciones instaladas.
mode:		blank
ignoreUninstalledPrograms: True
XSCREENSAVER
	chmod 644 "$xs"
	case "$base" in
		*/etc/skel) ;;
		*) chown "$(stat -c %u:%g "$base")" "$xs" 2>/dev/null || true ;;
	esac
	mv -n "$xs" "$base/.xscreensaver" 2>/dev/null || true
	rm -f "$xs"
	hizo=si
done
[ -n "$hizo" ] || exit 10
exit 0
