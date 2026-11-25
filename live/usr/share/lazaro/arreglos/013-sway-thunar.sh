#!/bin/sh
# Titulo: Sway tiene explorador de archivos: Thunar, que se abre con Windows + E
#
# Sway no trae explorador de archivos (Julián, 24 de noviembre de 2026).
# Copia de desktop-postinstall.sh desde esa fecha: Thunar y gvfs (USB y
# papelera), Thunar predeterminado para las carpetas en Sway
# (/etc/xdg/sway-mimeapps.list), Super+E en
# /etc/sway/config.d/50-lazaro-barra.conf y su nombre en la lista de
# atajos (sway-atajos).
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }
CONF="$R/etc/sway/config.d/50-lazaro-barra.conf"
MIME="$R/etc/xdg/sway-mimeapps.list"
ATAJOS="$R/usr/local/bin/sway-atajos"

# Sin la configuración de Sway de Lázaro no hace falta; si se instala
# después, se vuelve a mirar.
{ instalado sway && [ -f "$CONF" ]; } || exit 11

hizo=""
faltan=""
for p in thunar gvfs; do
	instalado "$p" || faltan="$faltan $p"
done
if [ -n "$faltan" ]; then
	# shellcheck disable=SC2086
	apk add -q $faltan || exit 1
	hizo=si
fi

if ! grep -q 'exec thunar' "$CONF"; then
	{
		echo "# Super+E abre el explorador de archivos (Thunar), como en Windows."
		echo "# Reemplaza a 'layout toggle split' (lo mismo se logra con Super+B y Super+V)."
		echo "bindsym --no-warn \$mod+e exec thunar"
	} >> "$CONF" || exit 1
	hizo=si
fi

if ! grep -qx 'inode/directory=thunar.desktop' "$MIME" 2>/dev/null; then
	mkdir -p "${MIME%/*}"
	if [ -f "$MIME" ]; then
		grep -v '^inode/directory=' "$MIME" > "$MIME.nuevo" || true
	else
		printf '[Default Applications]\n' > "$MIME.nuevo"
	fi
	grep -qx '\[Default Applications\]' "$MIME.nuevo" || printf '[Default Applications]\n' >> "$MIME.nuevo"
	awk '{ print } $0 == "[Default Applications]" { print "inode/directory=thunar.desktop" }' "$MIME.nuevo" > "$MIME" || exit 1
	rm -f "$MIME.nuevo"
	hizo=si
fi

if [ -f "$ATAJOS" ] && ! grep -q 'exec thunar/' "$ATAJOS"; then
	sed -i '/c ~ \/\^exec sway-atajos\/) return/a\        if (c ~ /^exec thunar/) return "Abrir el explorador de archivos"' "$ATAJOS" || exit 1
	hizo=si
fi

[ -n "$hizo" ] || exit 10
exit 0
