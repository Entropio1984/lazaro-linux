#!/bin/sh
# Titulo: IceWM: el botón "mostrar escritorio" tiene un icono que se ve en la barra (se nota al volver a entrar)
#
# El tema "moderno" de IceWM no traía icono propio para el botón "mostrar
# escritorio": IceWM ponía el suyo, oscuro, que se perdía en la barra azul
# marino. Las instalaciones nuevas lo traen desde el 16 de noviembre de
# 2026 (icewm_boton_escritorio de desktop-postinstall.sh, PR #46 del
# script; esto es una copia para los equipos instalados antes). No es un
# cambio de gusto: completa un archivo que le faltaba al tema, y si la
# persona ya puso el suyo no se toca.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
TEMA="$R/etc/icewm/themes/moderno"

# Sin el tema moderno no hay nada que arreglar hoy; si la persona instala
# IceWM después, ya vendrá con el botón.
[ -f "$TEMA/default.theme" ] || exit 11
[ ! -s "$TEMA/taskbar/desktop.xpm" ] || exit 10

mkdir -p "$TEMA/taskbar" || exit 1
awk 'BEGIN {
	n = 24
	print "/* XPM */"
	print "static char *escritorio[] = {"
	printf "\"%d %d 3 1\",\n\"  c None\",\n\". c #29b6f6\",\n\"# c #ffffff\",\n", n, n
	for (y = 0; y < n; y++) {
		fila = ""
		for (x = 0; x < n; x++) {
			p = " "
			if (x >= 2 && x <= 21 && y >= 3 && y <= 16)
				p = (x <= 3 || x >= 20 || y <= 4 || y >= 15) ? "#" : "."
			if (x >= 10 && x <= 13 && y >= 17 && y <= 18) p = "#"
			if (x >= 6 && x <= 17 && y >= 19 && y <= 20) p = "#"
			fila = fila p
		}
		printf "\"%s\"%s\n", fila, (y == n - 1) ? "" : ","
	}
	print "};"
}' > "$TEMA/taskbar/desktop.xpm.nuevo"
[ -s "$TEMA/taskbar/desktop.xpm.nuevo" ] &&
	mv -f "$TEMA/taskbar/desktop.xpm.nuevo" "$TEMA/taskbar/desktop.xpm" || {
	rm -f "$TEMA/taskbar/desktop.xpm.nuevo"; exit 1; }
exit 0
