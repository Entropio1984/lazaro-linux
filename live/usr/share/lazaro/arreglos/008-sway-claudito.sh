#!/bin/sh
# Titulo: Sway tiene una barra nueva: Claudito Shell Fusion
#
# Desde el 24 de noviembre de 2026 la barra de Sway es Claudito Shell
# Fusion (paquete lazaro-claudito, con Quickshell, del repositorio de
# Lázaro) en lugar de waybar. Es un cambio de panel, que estos arreglos no
# suelen hacer: lo pidió Julián para todos los equipos con Sway. Lo que la
# persona ajustó de waybar no se borra: waybar queda instalada y vuelve
# sola si Claudito no arranca.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

# Solo con Sway (si se instala después, se vuelve a mirar). Quickshell es
# de 64 bits: en la de 32 no hay Sway.
instalado sway || exit 11
instalado lazaro-claudito && exit 10
[ "$(uname -m)" = x86_64 ] || exit 10
apk add -q lazaro-claudito@lazaro quickshell@lazaro || exit 1
exit 0
