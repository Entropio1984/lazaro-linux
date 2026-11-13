#!/bin/sh
# Lista de paquetes de la edición Completa, para instalar sin internet.
#
#   sh perfil/paquetes-completa.sh SALIDA SCRIPT ÍNDICE... -- PAQUETE...
#
# SALIDA   archivo donde queda la lista (un nombre por línea)
# SCRIPT   desktop-postinstall.sh: se agrega todo lo que instala con
#          install_pkg/install_pkgs (con cualquier escritorio y equipo)
# ÍNDICE   APKINDEX.tar.gz de cada repositorio (main, community, el propio)
# PAQUETE  los de las listas del perfil (perfil/mkimg.lazaro.sh)
#
# mkimage.sh copia a la ISO cada paquete pedido con sus dependencias, pero
# no los que apk agrega solo al instalar (install_if): las traducciones
# (-lang, que el script pide con "lang"), los servicios (-openrc) o los
# complementos que aparecen cuando hay dos programas juntos. Sin ellos,
# la instalación sin internet quedaba a medias. Aquí se recorren los
# índices de Alpine: dependencias de todo lo pedido y, mientras aparezca
# algo nuevo, cada paquete cuyo install_if ya se cumple. Sobra un poco
# (algo que solo se instalaría con otra combinación), pero no falta nada.

set -eu

salida="$1"
script="$2"
shift 2
indices=""
while [ $# -gt 0 ] && [ "$1" != -- ]; do
	indices="$indices $1"
	shift
done
[ "${1:-}" = -- ] && shift

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for i in $indices; do
	tar -xzOf "$i" APKINDEX
	echo
done > "$tmp/indice"

# Lo que instala desktop-postinstall.sh: nombres fijos después de
# install_pkg o install_pkgs, fuera de los comentarios. Palabras que no
# son paquetes se descartan más abajo (no están en el índice).
grep -v '^[[:space:]]*#' "$script" |
	grep -oE 'install_pkgs? +[^;|&#)]*' |
	sed -E 's/install_pkgs? *//' |
	tr ' ' '\n' | tr -d "\"'" |
	grep -E '^[a-z0-9][a-z0-9._+-]*[a-z0-9]$' > "$tmp/semillas" || true
# LAZARO_EXCLUIR: paquetes del script que esta ISO no lleva (32 bits).
for x in ${LAZARO_EXCLUIR:-}; do
	grep -vx -- "$x" "$tmp/semillas" > "$tmp/semillas.n" || true
	mv "$tmp/semillas.n" "$tmp/semillas"
done
printf '%s\n' "$@" >> "$tmp/semillas"

awk '
	function limpiar(t) { sub(/[<>=~].*/, "", t); return t }
	# Paquete que cumple una dependencia: el nombre exacto o, si no, quien
	# la provee (so:, cmd:, pc: o un nombre virtual), el de más prioridad.
	function resolver(t) {
		t = limpiar(t)
		if (t in existe) return t
		if (t in provee) return provee[t]
		return ""
	}
	function agregar(n,    lista, k, j, d) {
		if (n == "" || (n in elegido)) return
		elegido[n] = 1
		pila[++tope] = n
		while (tope > 0) {
			x = pila[tope--]
			k = split(deps[x], lista, " ")
			for (j = 1; j <= k; j++) {
				if (lista[j] ~ /^!/) continue
				d = resolver(lista[j])
				if (d != "" && !(d in elegido)) { elegido[d] = 1; pila[++tope] = d }
			}
		}
	}
	FNR == 1 { archivo++ }
	archivo == 1 && /^P:/ { p = substr($0, 3); existe[p] = 1; next }
	archivo == 1 && /^D:/ { deps[p] = substr($0, 3); next }
	archivo == 1 && /^S:/ { peso[p] = substr($0, 3) + 0; next }
	archivo == 1 && /^i:/ { si[p] = substr($0, 3); next }
	archivo == 1 && /^k:/ { prio[p] = substr($0, 3) + 0; next }
	archivo == 1 && /^p:/ { prov[p] = substr($0, 3); next }
	archivo == 1 { next }
	archivo == 2 && NF { pedido[$1] = 1 }
	END {
		for (p in prov) {
			k = split(prov[p], lista, " ")
			for (j = 1; j <= k; j++) {
				v = limpiar(lista[j])
				if (!(v in provee) || prio[p] > prio[provee[v]]) provee[v] = p
			}
		}
		for (n in pedido) {
			if (n in existe) agregar(n)
			else desconocidos = desconocidos " " n
		}
		do {
			nuevos = 0
			for (q in si) {
				if (q in elegido) continue
				k = split(si[q], lista, " ")
				ok = 1
				for (j = 1; j <= k && ok; j++) {
					if (lista[j] ~ /^!/) { if (limpiar(substr(lista[j], 2)) in elegido) ok = 0 }
					else if (!(resolver(lista[j]) in elegido)) ok = 0
				}
				if (ok) { agregar(q); nuevos++ }
			}
		} while (nuevos > 0)
		for (n in elegido) {
			print n
			total += peso[n]
			if (n ~ /-lang$/) idiomas += peso[n]
			printf "%d %s\n", peso[n], n > pesos
		}
		printf "paquetes-completa: %d MB en total, %d MB en traducciones (-lang)\n", total / 1048576, idiomas / 1048576 > "/dev/stderr"
		if (desconocidos != "") print "paquetes-completa: no están en Alpine (se omiten):" desconocidos > "/dev/stderr"
	}
' pesos="$tmp/pesos" "$tmp/indice" "$tmp/semillas" > "$tmp/lista"
sort "$tmp/lista" > "$salida"

echo "paquetes-completa: $(wc -l < "$salida") paquetes en $salida"
# Los más pesados, para saber qué recortar si la ISO no cabe.
if [ -n "${LAZARO_PESOS:-}" ] && [ -s "$tmp/pesos" ]; then
	echo "paquetes-completa: los ${LAZARO_PESOS} más pesados (MB):"
	sort -rn "$tmp/pesos" | head -n "$LAZARO_PESOS" | awk '{ printf "  %6.1f %s\n", $1 / 1048576, $2 }'
fi
