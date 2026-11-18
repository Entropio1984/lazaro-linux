#!/bin/sh
# Titulo: El servicio de permisos (polkit) ya no aparece como fallido al encender (se nota al reiniciar)
#
# Al encender, NetworkManager despierta a ModemManager por D-Bus y este
# a polkit, antes de que OpenRC llegue a sus servicios. El polkit de
# OpenRC encuentra el nombre ocupado ("Lost the name
# org.freedesktop.PolicyKit1"), se reinicia en bucle y queda "failed"
# (visto en un Acer Aspire 4739, 17 de noviembre de 2026). Polkit
# seguía funcionando, pero el servicio se veía roto. Copia de
# ordenar_polkit de desktop-postinstall.sh: polkit va antes que
# NetworkManager y fwupd, y ModemManager antes que NetworkManager.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"

# Sin el servicio de polkit no hay nada que ordenar; si se instala
# después, se vuelve a mirar.
[ -e "$R/etc/init.d/polkit" ] || exit 11

tiene() { grep -q '^rc_before=' "$R/etc/conf.d/$1" 2>/dev/null; }
tiene polkit && tiene modemmanager && exit 10

mkdir -p "$R/etc/conf.d" || exit 1
if ! tiene polkit; then
	printf '%s\n' \
		'# desktop-postinstall.sh: polkit arranca antes que quienes lo despiertan' \
		'# por D-Bus; si no, su servicio choca con ese polkit y queda "failed".' \
		'rc_before="networkmanager fwupd"' >> "$R/etc/conf.d/polkit" || exit 1
fi
if ! tiene modemmanager; then
	printf '%s\n' \
		'# desktop-postinstall.sh: ModemManager arranca antes que NetworkManager,' \
		'# que si no lo despierta por D-Bus y su servicio queda "failed".' \
		'rc_before="networkmanager"' >> "$R/etc/conf.d/modemmanager" || exit 1
fi
exit 0
