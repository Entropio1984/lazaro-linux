# shellcheck shell=sh
# Traducción de los textos de las herramientas de Lázaro (programas de
# shell). Se carga con:
#
#   if [ -r "${LAZARO_TEXTO_DIR:-/usr/share/lazaro}/texto.sh" ]; then
#   	. "${LAZARO_TEXTO_DIR:-/usr/share/lazaro}/texto.sh"
#   else
#   	_() { printf '%s' "$1"; }
#   fi
#
# y se usa así:  zenity --text="$(_ 'Listo.')"
#                printf "$(_ 'Instalados: %s')\n" "$n"
#
# Los textos se escriben en español en el programa; las traducciones
# están en idiomas/<idioma>.po (formato gettext, el de siempre para
# traducir programas libres). Si el idioma de la sesión es español, o no
# hay archivo, sale el texto tal cual. Un idioma sin archivo propio usa
# el inglés (más gente lo entiende que el español).
# Un "\n" escrito en el texto es un salto de línea.

LAZARO_TEXTO_DIR="${LAZARO_TEXTO_DIR:-/usr/share/lazaro}"

# Archivo de traducción del idioma de la sesión, o vacío (español).
lazaro_texto_archivo() {
	_lt_i="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
	_lt_i="${_lt_i%%.*}"
	_lt_i="${_lt_i%%@*}"
	case "$_lt_i" in
		"" | C | POSIX | es | es_*) return 0 ;;
	esac
	_lt_d="$LAZARO_TEXTO_DIR/idiomas"
	for _lt_f in "$_lt_d/$_lt_i.po" "$_lt_d/${_lt_i%%_*}.po" "$_lt_d/${_lt_i%%_*}"_*.po "$_lt_d/en.po"; do
		[ -r "$_lt_f" ] && { printf '%s' "$_lt_f"; return 0; }
	done
	return 0
}
LAZARO_TEXTO_PO="$(lazaro_texto_archivo)"

_() {
	if [ -z "$LAZARO_TEXTO_PO" ]; then
		LT_CLAVE="$1" awk 'BEGIN { c = ENVIRON["LT_CLAVE"]; gsub(/\\n/, "\n", c); printf "%s", c }'
		return 0
	fi
	LT_CLAVE="$1" awk '
		# Las comillas y barras de un texto de .po, a texto normal.
		function sin_escapes(s,    r, c, i) {
			r = ""
			for (i = 1; i <= length(s); i++) {
				c = substr(s, i, 1)
				if (c == "\\" && i < length(s)) {
					i++; c = substr(s, i, 1)
					if (c == "n") c = "\n"
					else if (c == "t") c = "\t"
				}
				r = r c
			}
			return r
		}
		function cadena(l) { sub(/^[^"]*"/, "", l); sub(/"[ \t]*$/, "", l); return sin_escapes(l) }
		function cerrar() {
			if (hallado == "" && estado == "str" && id == clave && str != "") hallado = str
			return hallado != ""
		}
		BEGIN {
			clave = ENVIRON["LT_CLAVE"]
			gsub(/\\n/, "\n", clave)
		}
		/^msgid / { if (cerrar()) exit; estado = "id"; id = cadena($0); str = ""; next }
		/^msgstr / { estado = "str"; str = cadena($0); next }
		/^"/ { if (estado == "id") id = id cadena($0); else if (estado == "str") str = str cadena($0); next }
		/^[ \t]*(#|$)/ { if (cerrar()) exit; estado = ""; next }
		END {
			# Con "exit" se llega aquí ya con el texto hallado.
			if (hallado == "") cerrar()
			if (hallado != "") printf "%s", hallado
			else printf "%s", clave
		}' "$LAZARO_TEXTO_PO"
}
