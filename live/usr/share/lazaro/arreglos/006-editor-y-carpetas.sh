#!/bin/sh
# Titulo: LXQt y Sway tienen editor de texto, y los botones "Abrir la carpeta" funcionan en todos los escritorios
#
# LXQt y Sway no traen editor de texto: un .txt no tenía con qué
# abrirse. Y LXQt no trae xdg-open (paquete xdg-utils), que usan los
# botones "Abrir la carpeta" del Diagnóstico y los enlaces de la
# Bienvenida: no hacían nada (VM con la Completa, 23 de noviembre de
# 2026). Copia de install_daily_apps de desktop-postinstall.sh desde esa
# fecha: FeatherPad en LXQt, Mousepad en Sway y xdg-utils en todos.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

# Sin escritorio no hace falta; si se instala uno después, se vuelve a
# mirar.
instalado xorg-server || instalado sway || exit 11

faltan=""
instalado xdg-utils || faltan="xdg-utils"
if instalado lxqt-desktop && ! instalado featherpad; then
	faltan="$faltan featherpad"
fi
if instalado sway && ! instalado mousepad; then
	faltan="$faltan mousepad"
fi
[ -n "$faltan" ] || exit 10
# shellcheck disable=SC2086
apk add -q $faltan || exit 1
exit 0
