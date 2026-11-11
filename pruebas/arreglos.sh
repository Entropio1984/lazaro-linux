#!/bin/sh
# Prueba las mejoras para equipos ya instalados sin tocar el equipo:
#   - lazaro-arreglos: corre cada arreglo una sola vez y en orden, anota
#     lo hecho, reintenta lo que falló y no corre nada en un sistema
#     recién instalado;
#   - lazaro-actualizar-raiz: repositorio, actualización y arreglos, en
#     ese orden, con programas falsos;
#   - los arreglos de verdad (live/usr/share/lazaro/arreglos): bien
#     escritos, y el de la tienda en un sistema de mentira;
#   - la ventana del Actualizador reconoce las mejoras aplicadas.
#
#   pruebas/arreglos.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-arreglos"
RAIZ_PROG="$DIR/live/usr/sbin/lazaro-actualizar-raiz"
REALES="$DIR/live/usr/share/lazaro/arreglos"
TMP="$(mktemp -d)"
[ -d "$TMP" ] || exit 1
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }
es() { if eval "$2"; then ok "$1"; else mal "$1"; fi; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else mal "$1: salió [$2], se esperaba [$3]"; fi; }

# --- lazaro-arreglos con arreglos de mentira --------------------------------
A="$TMP/arreglos"
mkdir -p "$A"
export LAZARO_ARREGLOS_DIR="$A" LAZARO_ARREGLOS_ESTADO="$TMP/estado/arreglos" \
	LAZARO_ARREGLOS_LOG="$TMP/arreglos.log" LAZARO_ARREGLOS_CANDADO="$TMP/candado"
arreglo() { # NOMBRE TÍTULO CUERPO
	printf '#!/bin/sh\n# Titulo: %s\necho "%s" >> "%s/corridos"\n%s\n' "$2" "$1" "$TMP" "$3" > "$A/$1.sh"
}
arreglo 002-segundo "Segundo arreglo" "exit 10"
arreglo 001-primero "Primer arreglo" "exit 0"
arreglo 003-tercero "Tercer arreglo" '[ -e "'"$TMP"'/hay-internet" ] || exit 1'
: > "$A/LEEME.md"
: > "$A/sin-numero.sh"

igual "al principio, todos pendientes" "$(sh "$PROG" --listar | cut -f1,2 | tr '\t\n' ' ;')" \
	"001-primero pendiente;002-segundo pendiente;003-tercero pendiente;"
igual "la lista trae el título" "$(sh "$PROG" --listar | sed -n 1p | cut -f3)" "Primer arreglo"

sh "$PROG" --aplicar > "$TMP/sal1.txt"
igual "corren en orden, y solo los que son arreglos" "$(tr '\n' ' ' < "$TMP/corridos")" "001-primero 002-segundo 003-tercero "
es "el aplicado se anuncia a la ventana" 'grep -qx "# Mejora aplicada: Primer arreglo" "$TMP/sal1.txt"'
es "el que no hacía falta no se anuncia" '! grep -q "Segundo" "$TMP/sal1.txt"'
es "el que falló no se anuncia como aplicado, y se avisa" '! grep -q "Tercer" "$TMP/sal1.txt" && grep -q "^# Quedaron 1 mejoras" "$TMP/sal1.txt"'
igual "queda anotado lo hecho y lo que no hizo falta" "$(sh "$PROG" --listar | cut -f1,2 | tr '\t\n' ' ;')" \
	"001-primero hecho;002-segundo sin-falta;003-tercero pendiente;"
es "el detalle queda en el registro" 'grep -q "003-tercero: Tercer arreglo" "$TMP/arreglos.log" && grep -q "no se pudo (código 1)" "$TMP/arreglos.log"'

: > "$TMP/corridos"
sh "$PROG" --aplicar > "$TMP/sal2.txt"
igual "la segunda vez solo se reintenta el que falló" "$(tr '\n' ' ' < "$TMP/corridos")" "003-tercero "
: > "$TMP/hay-internet"
: > "$TMP/corridos"
sh "$PROG" --aplicar > "$TMP/sal3.txt"
es "cuando ya puede, se aplica y se anuncia" 'grep -qx "# Mejora aplicada: Tercer arreglo" "$TMP/sal3.txt"'
: > "$TMP/corridos"
sh "$PROG" --aplicar > "$TMP/sal4.txt"
es "con todo hecho no corre nada ni dice nada" '[ ! -s "$TMP/corridos" ] && [ ! -s "$TMP/sal4.txt" ]'

# Un arreglo nuevo que llega con una actualización.
arreglo 004-nuevo "Arreglo que llegó después" "exit 0"
sh "$PROG" --aplicar > "$TMP/sal5.txt"
igual "un arreglo nuevo corre solo él" "$(tr '\n' ' ' < "$TMP/corridos")" "004-nuevo "

# Otro lazaro-arreglos trabajando: este no hace nada.
arreglo 005-otro "Otro" "exit 0"
mkdir "$TMP/candado"; echo $$ > "$TMP/candado/pid"
: > "$TMP/corridos"
sh "$PROG" --aplicar > /dev/null
es "con otro en curso no corre nada" '[ ! -s "$TMP/corridos" ]'
# Un candado que quedó de un apagón no estorba.
echo 999999 > "$TMP/candado/pid"
sh "$PROG" --aplicar > /dev/null
es "un candado viejo no estorba, y se quita al terminar" '[ "$(cat "$TMP/corridos")" = 005-otro ] && [ ! -e "$TMP/candado" ]'

# Un arreglo que se queda colgado se corta.
arreglo 006-colgado "Colgado" "sleep 30"
LAZARO_ARREGLOS_PLAZO=1 sh "$PROG" --aplicar > "$TMP/sal6.txt"
es "un arreglo colgado se corta y queda pendiente" 'sh "$PROG" --listar | grep -q "^006-colgado	pendiente"'
rm "$A/006-colgado.sh"

# Sistema recién instalado: todo anotado sin correr.
unset LAZARO_ARREGLOS_DIR LAZARO_ARREGLOS_ESTADO LAZARO_ARREGLOS_LOG
R="$TMP/raiz"
mkdir -p "$R/usr/share/lazaro"
cp -r "$A" "$R/usr/share/lazaro/arreglos"
: > "$TMP/corridos"
igual "--marcar con --raiz" "$(sh "$PROG" --marcar --raiz "$R")" "LAZARO-ARREGLOS-MARCADOS 5"
es "al instalar no corre ninguno y quedan anotados" '[ ! -s "$TMP/corridos" ] && [ "$(grep -c " instalacion " "$R/var/lib/lazaro/arreglos")" = 5 ]'
sh "$PROG" --marcar --raiz "$R" > /dev/null
es "marcar dos veces no repite" '[ "$(wc -l < "$R/var/lib/lazaro/arreglos")" = 5 ]'
rc=0; sh "$PROG" --otra 2>/dev/null || rc=$?
igual "una orden desconocida se rechaza" "$rc" 2
unset LAZARO_ARREGLOS_CANDADO

# --- lazaro-actualizar-raiz -------------------------------------------------
B="$TMP/bin"
mkdir -p "$B"
falso() { # NOMBRE CÓDIGO [SALIDA]
	printf '#!/bin/sh\necho "%s $*" >> "%s/llamadas"\n[ -z "%s" ] || echo "%s"\nexit %s\n' "$1" "$TMP" "${3:-}" "${3:-}" "$2" > "$B/$1"
	chmod 755 "$B/$1"
}
actualizar() {
	: > "$TMP/llamadas"
	rc=0
	LAZARO_ACTUALIZAR_REPOSITORIO="$B/repositorio" LAZARO_ACTUALIZAR_SISTEMA="$B/sistema" \
		LAZARO_ACTUALIZAR_ARREGLOS="$B/arreglos" sh "$RAIZ_PROG" "$@" > "$TMP/act.txt" 2>&1 || rc=$?
}
falso repositorio 0
falso sistema 0 "# apk upgrade"
falso arreglos 0 "# Mejora aplicada: Una mejora"
actualizar
igual "repositorio, sistema y arreglos, en ese orden" "$(tr '\n' ';' < "$TMP/llamadas")" \
	"repositorio --sincronizar;sistema ;arreglos --aplicar;"
es "empieza con un paso para la ventana y termina bien" '[ "$rc" = 0 ] && [ "$(head -n 1 "$TMP/act.txt")" = "# Buscando las mejoras de Lázaro…" ]'
es "todas sus líneas llevan el prefijo de paso" '! grep -qv "^# " "$TMP/act.txt"'
actualizar --nueva-version
es "el cambio de versión de Alpine se pasa al actualizador" 'grep -qx "sistema --nueva-version" "$TMP/llamadas"'
falso repositorio 1
actualizar
es "sin repositorio (sin internet) se actualiza igual" '[ "$rc" = 0 ] && grep -q "^sistema" "$TMP/llamadas" && grep -q "^# No se pudo consultar" "$TMP/act.txt"'
falso repositorio 0
falso sistema 3
actualizar
es "si la actualización falla, se dice (y los arreglos se intentan)" '[ "$rc" = 3 ] && grep -q "^arreglos" "$TMP/llamadas"'
falso sistema 75
actualizar
es "con otra actualización en curso no se aplican arreglos" '[ "$rc" = 75 ] && ! grep -q "^arreglos" "$TMP/llamadas"'

# --- Los arreglos de verdad -------------------------------------------------
mal_escritos=""
anterior=""
for a in "$REALES"/*.sh; do
	b="$(basename "$a")"
	case "$b" in
		[0-9][0-9][0-9]-*.sh) ;;
		*) mal_escritos="$mal_escritos $b(nombre)"; continue ;;
	esac
	sh -n "$a" 2>/dev/null || mal_escritos="$mal_escritos $b(sintaxis)"
	[ -n "$(sed -n 's/^# Titulo: *//p' "$a")" ] || mal_escritos="$mal_escritos $b(sin-título)"
	[ "${b%%-*}" != "$anterior" ] || mal_escritos="$mal_escritos $b(número-repetido)"
	anterior="${b%%-*}"
done
igual "arreglos bien escritos (nombre, sintaxis, título, número único)" "$mal_escritos" ""
igual "lazaro-arreglos los ve todos" "$(sh "$PROG" --listar --raiz "$DIR/live" | wc -l)" "$(ls "$REALES"/*.sh | wc -l)"

# 001-tienda en un sistema de mentira, con apk y rc-update falsos.
T="$TMP/tienda"
mkdir -p "$T/lib/apk/db" "$T/etc/init.d" "$T/etc/runlevels/default"
cat > "$B/apk" <<EOF2
#!/bin/sh
echo "apk \$*" >> "$TMP/llamadas"
[ ! -e "$TMP/sin-internet" ] || exit 1
for p in "\$@"; do
	case "\$p" in
		apk-polkit-rs-openrc) : > "$T/etc/init.d/apk-polkit-server"; chmod 755 "$T/etc/init.d/apk-polkit-server"; echo "P:\$p" >> "$T/lib/apk/db/installed" ;;
		alpine-*) echo "P:\$p" >> "$T/lib/apk/db/installed" ;;
	esac
done
EOF2
cat > "$B/rc-update" <<EOF2
#!/bin/sh
echo "rc-update \$*" >> "$TMP/llamadas"
[ "\$1" = add ] && : > "$T/etc/runlevels/\$3/\$2"
exit 0
EOF2
falso rc-service 0
chmod 755 "$B/apk" "$B/rc-update"
tienda() { rc=0; : > "$TMP/llamadas"; PATH="$B:$PATH" LAZARO_ARREGLO_RAIZ="$T" sh "$REALES/001-tienda.sh" > /dev/null 2>&1 || rc=$?; }
: > "$T/lib/apk/db/installed"
tienda
es "tienda: sin tienda instalada no hace falta" '[ "$rc" = 10 ] && [ ! -s "$TMP/llamadas" ]'
echo "P:gnome-software" > "$T/lib/apk/db/installed"
: > "$TMP/sin-internet"
tienda
es "tienda: sin internet queda pendiente" '[ "$rc" != 0 ] && [ "$rc" != 10 ] && [ ! -e "$T/etc/periodic/hourly/alpine-tienda-catalogo" ]'
rm "$TMP/sin-internet"
tienda
es "tienda: activa el servicio y pone la tarea del catálogo" '[ "$rc" = 0 ] && [ -e "$T/etc/runlevels/default/apk-polkit-server" ] && [ -x "$T/etc/periodic/hourly/alpine-tienda-catalogo" ] && grep -qx "P:alpine-appstream-downloader" "$T/lib/apk/db/installed" && [ -e "$T/etc/runlevels/default/crond" ]'
es "tienda: la tarea tiene buena sintaxis" 'sh -n "$T/etc/periodic/hourly/alpine-tienda-catalogo"'
tienda
es "tienda: ya arreglada, no hace falta" '[ "$rc" = 10 ] && [ ! -s "$TMP/llamadas" ]'
printf 'P:discover\nP:alpine-appstream-downloader\n' > "$T/lib/apk/db/installed"
rm -rf "$T/etc/periodic" "$T/etc/runlevels/default/apk-polkit-server"
tienda
es "tienda: con Discover solo hace falta el catálogo" '[ "$rc" = 0 ] && [ -x "$T/etc/periodic/hourly/alpine-tienda-catalogo" ] && ! grep -q polkit "$TMP/llamadas"'

# --- Lo que va al paquete y al sistema instalado ----------------------------
for p in lazaro-arreglos lazaro-actualizar-raiz; do
	es "$p va en el paquete y lo copia el instalador" 'grep -q "$p" "$DIR/repo/herramientas.sh" && grep -q "/usr/sbin/$p" "$DIR/live/usr/sbin/lazaro-instalar"'
	es "sintaxis de $p" 'sh -n "$DIR/live/usr/sbin/$p"'
done
es "los arreglos van en el paquete" 'grep -q "usr/share/lazaro/arreglos" "$DIR/repo/herramientas.sh"'

# --- La ventana del Actualizador --------------------------------------------
if command -v python3 >/dev/null 2>&1; then
	cat > "$TMP/act.py" <<'EOS'
import importlib.machinery, importlib.util, sys
cargador = importlib.machinery.SourceFileLoader("act", sys.argv[1])
act = importlib.util.module_from_spec(importlib.util.spec_from_loader("act", cargador))
cargador.exec_module(act)
casos = [
    ("reconoce una mejora", act.mejora_de(act.limpiar("# Mejora aplicada: Se activó la tienda\r")), "Se activó la tienda"),
    ("un paso normal no es una mejora", act.mejora_de(act.limpiar("# (1/3) Upgrading musl")), None),
    ("sin título no cuenta", act.mejora_de("Mejora aplicada: "), None),
    ("sin lazaro-actualizar-raiz usa el actualizador de siempre", act.orden_de_actualizar(""),
     ["pkexec", sys.argv[2] if act.os.access(act.RAIZ_LAZARO, act.os.X_OK) else act.RAIZ]),
]
act.RAIZ_LAZARO = sys.argv[2]
casos.append(("con lazaro-actualizar-raiz, pasa por él", act.orden_de_actualizar("--nueva-version"),
              ["pkexec", sys.argv[2], "--nueva-version"]))
mal = [n for n, sale, espera in casos if sale != espera]
for n, sale, espera in casos:
    print("%s  %s" % ("ok  " if sale == espera else "FALLO", n))
sys.exit(1 if mal else 0)
EOS
	es "actualizador: mejoras aplicadas y orden" 'env -u LAZARO_ACTUALIZADOR_ORDEN python3 "$TMP/act.py" "$DIR/live/usr/sbin/lazaro-actualizador" "$RAIZ_PROG" > "$TMP/actpy.txt" 2>&1'
	cat "$TMP/actpy.txt"
	# El anuncio que escribe lazaro-arreglos es el que la ventana busca.
	es "lazaro-arreglos y la ventana usan el mismo anuncio" 'grep -q "^MEJORA = \"Mejora aplicada: \"$" "$DIR/live/usr/sbin/lazaro-actualizador" && grep -q "echo \"# Mejora aplicada: " "$PROG"'
fi

echo
if [ "$fallos" -eq 0 ]; then
	echo "Las $n pruebas pasaron."
else
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
