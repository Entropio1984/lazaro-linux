#!/bin/sh
# Titulo: IceWM: la tecla Imprimir Pantalla abre el programa de capturas (se nota al volver a entrar)
#
# Antes, en IceWM, Imprimir guardaba la pantalla completa con scrot, sin
# ventana. Las instalaciones nuevas traen Capturas de GNOME
# (gnome-screenshot) desde el 16 de noviembre de 2026 (icewm_teclas de
# desktop-postinstall.sh, PR #45 del script; esto es una copia para los
# equipos instalados antes): Imprimir abre su ventana, Mayús+Imprimir
# captura una zona y Alt+Imprimir la ventana activa. Si se cambia allá el
# ayudante "captura" o las teclas, hace falta un arreglo nuevo: este ya
# corrió en los equipos.
#
# Solo toca el archivo de teclas del sistema si lo generó el script; lo
# que la persona puso en ~/.icewm/keys no se toca (el ayudante viejo
# sigue funcionando desde ahí, ahora con la ventana).
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

TECLAS="$R/etc/icewm/keys"
AYUDANTE="$R/usr/local/libexec/icewm-lxde/captura"

# Sin la sesión de IceWM que arma el script no hay nada que arreglar hoy;
# si la persona la instala después, se vuelve a mirar.
grep -q "Generado por desktop-postinstall.sh" "$TECLAS" 2>/dev/null || exit 11
if instalado gnome-screenshot && grep -q 'captura --area' "$TECLAS" &&
	grep -q gnome-screenshot "$AYUDANTE" 2>/dev/null; then
	exit 10
fi

instalado gnome-screenshot || apk add -q gnome-screenshot || exit 1

# A un archivo aparte y después a su lugar: si no se puede escribir (disco
# lleno), el arreglo queda pendiente en vez de dejar archivos a medias.
mkdir -p "${AYUDANTE%/*}" || exit 1
cat > "$AYUDANTE.nuevo" <<'CAPTURA'
#!/bin/sh
# Generado por desktop-postinstall.sh: captura de pantalla con Imprimir.
modo="${1:---interactive}"
if command -v gnome-screenshot >/dev/null 2>&1; then
    exec gnome-screenshot "$modo"
fi
d="$(xdg-user-dir PICTURES 2>/dev/null)"
[ -n "$d" ] && [ -d "$d" ] || d="$HOME"
case "$modo" in
    --area) exec scrot -s "$d/Captura-%Y-%m-%d-%H%M%S.png" ;;
    --window) exec scrot -u "$d/Captura-%Y-%m-%d-%H%M%S.png" ;;
    *) exec scrot "$d/Captura-%Y-%m-%d-%H%M%S.png" ;;
esac
CAPTURA
[ -s "$AYUDANTE.nuevo" ] && chmod 755 "$AYUDANTE.nuevo" && mv -f "$AYUDANTE.nuevo" "$AYUDANTE" || {
	rm -f "$AYUDANTE.nuevo"; exit 1; }

# Las teclas de captura nuevas en lugar de la vieja; el resto del
# archivo queda igual.
{
	grep -vE '^key "(Shift\+|Alt\+)?Print"' "$TECLAS"
	echo 'key "Print"                 /usr/local/libexec/icewm-lxde/captura'
	echo 'key "Shift+Print"           /usr/local/libexec/icewm-lxde/captura --area'
	echo 'key "Alt+Print"             /usr/local/libexec/icewm-lxde/captura --window'
} > "$TECLAS.nuevo"
grep -q 'captura --area' "$TECLAS.nuevo" && mv -f "$TECLAS.nuevo" "$TECLAS" || {
	rm -f "$TECLAS.nuevo"; exit 1; }
exit 0
