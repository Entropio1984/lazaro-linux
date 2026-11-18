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

# Lo que falta en rc_before de /etc/conf.d/SERVICIO (vale la última
# línea, como en OpenRC). Si alguien ya puso su propio orden, se suma.
faltan() { # SERVICIO NOMBRES...
	f="$R/etc/conf.d/$1"; shift
	actual="$(sed -n 's/^rc_before="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$f" 2>/dev/null | tail -n 1)"
	for n in "$@"; do
		case " $actual " in *" $n "*) ;; *) printf '%s ' "$n" ;; esac
	done
}
poner() { # SERVICIO COMENTARIO NOMBRES...
	s="$1" c="$2"; shift 2
	falta="$(faltan "$s" "$@")"
	[ -n "$falta" ] || return 0
	actual="$(sed -n 's/^rc_before="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$R/etc/conf.d/$s" 2>/dev/null | tail -n 1)"
	nuevo="$(echo $actual $falta)"
	printf '%s\nrc_before="%s"\n' "$c" "$nuevo" >> "$R/etc/conf.d/$s"
}

[ -z "$(faltan polkit networkmanager fwupd)$(faltan modemmanager networkmanager)" ] && exit 10

mkdir -p "$R/etc/conf.d" || exit 1
poner polkit '# Lázaro: polkit arranca antes que quienes lo despiertan por D-Bus; si no, su servicio choca con ese polkit y queda "failed".' \
	networkmanager fwupd || exit 1
poner modemmanager '# Lázaro: ModemManager arranca antes que NetworkManager, que si no lo despierta por D-Bus y su servicio queda "failed".' \
	networkmanager || exit 1
exit 0
