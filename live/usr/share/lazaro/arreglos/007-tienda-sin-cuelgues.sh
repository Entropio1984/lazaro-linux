#!/bin/sh
# Titulo: La lista de programas de la tienda ya no se queda colgada con una conexión lenta
#
# El programa de Alpine que baja la lista de la tienda
# (alpine-appstream-downloader) descarga sin tiempo límite: si el
# servidor deja de mandar datos a mitad de camino, esperaba para siempre
# y la tienda seguía vacía (VM de Julián, 23 de noviembre de 2026). Desde
# esa fecha desktop-postinstall.sh lo corre con 60 segundos por conexión
# y hasta 3 intentos; esto cambia esa línea en la tarea de cada hora de
# los equipos ya instalados (la que dejaron la instalación o el arreglo
# 001-tienda).
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
TAREA="$R/etc/periodic/hourly/alpine-tienda-catalogo"

# Sin tarea no hay tienda (todavía): se vuelve a mirar más adelante.
[ -e "$TAREA" ] || exit 11
# Ya tiene el tiempo límite, o es otra versión que no se toca.
grep -q 'timeout=60' "$TAREA" && exit 10
grep -qx '    timeout 600 alpine-appstream-downloader || exit 1' "$TAREA" || exit 10

nuevo="$TAREA.nuevo"
cat > "$nuevo.bloque" <<'BLOQUE' || exit 1
    # El programa de Alpine descarga con requests sin tiempo limite: si
    # la conexion se traba a mitad de camino, esperaba para siempre.
    # Cada conexion tiene 60 segundos sin recibir nada; si se traba, se
    # intenta otra vez (3 veces como mucho) y, si no, la hora siguiente.
    _ok=no
    for _intento in 1 2 3; do
        if timeout 240 python3 -c 'import functools, requests, runpy, shutil
for n in ("get", "head"):
    setattr(requests, n, functools.partial(getattr(requests, n), timeout=60))
runpy.run_path(shutil.which("alpine-appstream-downloader"), run_name="__main__")'; then
            _ok=si
            break
        fi
        echo "Intento $_intento: la descarga se trabo o fallo."
    done
    [ "$_ok" = si ] || exit 1
BLOQUE
awk -v bloque="$nuevo.bloque" '
	$0 == "    timeout 600 alpine-appstream-downloader || exit 1" {
		while ((getline l < bloque) > 0) print l
		next
	}
	{ print }
' "$TAREA" > "$nuevo" || { rm -f "$nuevo" "$nuevo.bloque"; exit 1; }
rm -f "$nuevo.bloque"
sh -n "$nuevo" || { rm -f "$nuevo"; exit 1; }
chmod 755 "$nuevo" && mv "$nuevo" "$TAREA" || exit 1
exit 0
