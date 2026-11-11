#!/bin/sh
# Titulo: Se activó la tienda de programas (antes solo mostraba lo ya instalado)
#
# La tienda (Software de GNOME o Discover) no mostraba los programas de
# Alpine porque faltaban dos cosas: el servicio con que la tienda instala
# programas (apk-polkit-server) estaba sin activar y la lista de
# programas con sus iconos (catálogo AppStream) no se descargaba nunca.
# Las instalaciones nuevas ya lo traen arreglado desde el 11 de noviembre
# de 2026 (setup_software_store de desktop-postinstall.sh, del que esto
# es una copia para los equipos instalados antes). Si se cambia allá la
# tarea alpine-tienda-catalogo, hace falta un arreglo nuevo: este ya
# corrió en los equipos.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

gnome=no
instalado gnome-software && gnome=si
[ "$gnome" = si ] || instalado discover || exit 10

TAREA="$R/etc/periodic/hourly/alpine-tienda-catalogo"
if [ -x "$TAREA" ] && instalado alpine-appstream-downloader &&
	{ [ "$gnome" = no ] || [ -e "$R/etc/runlevels/default/apk-polkit-server" ]; }; then
	exit 10
fi

if [ "$gnome" = si ]; then
	instalado apk-polkit-rs-openrc || apk add -q apk-polkit-rs-openrc || exit 1
	if [ -x "$R/etc/init.d/apk-polkit-server" ]; then
		rc-update add apk-polkit-server default || exit 1
		rc-service apk-polkit-server start || true
	fi
fi
instalado alpine-appstream-downloader || apk add -q alpine-appstream-downloader || exit 1

mkdir -p "$R/etc/periodic/hourly"
cat > "$TAREA" <<'TAREAEOF'
#!/bin/sh
# Generado por desktop-postinstall.sh: descarga la lista de programas de
# Alpine que muestra la tienda de aplicaciones (catalogo AppStream, en
# /var/lib/swcatalog). Corre cada hora, pero solo descarga si pasaron
# 24 horas desde la ultima vez que funciono; sin internet, lo intenta
# la hora siguiente.
# Si falta el programa que la descarga (se instalo sin internet), se
# instala primero. Los errores quedan en /var/log/alpine-tienda-catalogo.log.
marca=/var/lib/swcatalog/.ultima-descarga
[ -n "$(find "$marca" -mmin -1430 2>/dev/null)" ] && exit 0
# Si "Actualizar el sistema" esta trabajando, no estorbar.
[ -d /run/alpine-update.lock ] && exit 0
log=/var/log/alpine-tienda-catalogo.log
{
    date
    command -v alpine-appstream-downloader >/dev/null 2>&1 \
        || timeout 600 apk add -q alpine-appstream-downloader || exit 1
    timeout 600 alpine-appstream-downloader || exit 1
    mkdir -p /var/lib/swcatalog
    touch "$marca"
    echo "Catalogo descargado."
} >"$log" 2>&1
TAREAEOF
chmod 755 "$TAREA"
rc-update add crond default >/dev/null 2>&1 || true

# La lista se descarga ya; si ahora no se puede, la tarea lo intenta
# cada hora.
[ -n "$R" ] || timeout 700 "$TAREA" || true
exit 0
