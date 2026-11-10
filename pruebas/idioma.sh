#!/bin/sh
# Prueba el idioma y el teclado de la sesión de prueba sin abrir ventanas:
#  - lazaro-traducciones: de un paquete de traducción (-lang, que trae
#    todos los idiomas) se queda solo con el idioma pedido.
#  - lazaro-idioma: la lista de idiomas y teclados, y lo que escribe en
#    /etc al elegir (en una carpeta de prueba).
#  - el botón "Idioma y teclado" de la Bienvenida: solo en la live.
# En Alpine (con apk e internet) además descarga un paquete -lang de
# verdad y saca el español.
#
#   pruebas/idioma.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRAD="$DIR/live/usr/sbin/lazaro-traducciones"
IDIOMA="$DIR/live/usr/sbin/lazaro-idioma"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }
es() { if eval "$2"; then ok "$1"; else mal "$1"; fi; }

es "sintaxis de lazaro-traducciones" 'sh -n "$TRAD"'

# 1. Qué archivos de un paquete -lang son de cada idioma.
cat > "$TMP/rutas" <<'EOS'
./.PKGINFO
.SIGN.RSA.alpine-devel.rsa.pub
usr/share/locale/
usr/share/locale/es/LC_MESSAGES/xfce4-panel.mo
usr/share/locale/es_MX/LC_MESSAGES/gtk30.mo
usr/share/locale/et/LC_MESSAGES/xfce4-panel.mo
usr/share/locale/eo/LC_MESSAGES/xfce4-panel.mo
usr/share/locale/pt/LC_MESSAGES/xfce4-panel.mo
usr/share/locale/pt_BR/LC_MESSAGES/xfce4-panel.mo
usr/share/locale/ca@valencia/LC_MESSAGES/xfce4-panel.mo
usr/share/i18n/locales/musl/es_ES.UTF-8
usr/share/lxqt/translations/lxqt-panel/lxqt-panel_es.qm
usr/share/qt6/translations/qtbase_pt_BR.qm
usr/share/qt6/translations/qtbase_de.qm
EOS
sh "$TRAD" filtrar es_CO.UTF-8 < "$TMP/rutas" > "$TMP/es"
es "español: las carpetas es y es_MX" 'grep -qx "usr/share/locale/es/LC_MESSAGES/xfce4-panel.mo" "$TMP/es" && grep -qx "usr/share/locale/es_MX/LC_MESSAGES/gtk30.mo" "$TMP/es"'
es "español: fechas de musl y archivos de Qt" 'grep -qx "usr/share/i18n/locales/musl/es_ES.UTF-8" "$TMP/es" && grep -qx "usr/share/lxqt/translations/lxqt-panel/lxqt-panel_es.qm" "$TMP/es"'
es "español: nada de estonio (et), esperanto (eo) ni portugués" '! grep -qe /et/ -e /eo/ -e /pt "$TMP/es"'
es "español: ni archivos de control del paquete ni carpetas" '! grep -qe PKGINFO -e SIGN -e "/$" "$TMP/es"'
es "español: 4 archivos" '[ "$(wc -l < "$TMP/es")" = 4 ]'
sh "$TRAD" filtrar pt_BR < "$TMP/rutas" > "$TMP/pt"
es "portugués: pt, pt_BR y qtbase_pt_BR" '[ "$(wc -l < "$TMP/pt")" = 3 ] && grep -q qtbase_pt_BR "$TMP/pt"'
es "catalán (ca@valencia)" '[ "$(sh "$TRAD" filtrar ca_ES.UTF-8 < "$TMP/rutas")" = "usr/share/locale/ca@valencia/LC_MESSAGES/xfce4-panel.mo" ]'
rc=0; sh "$TRAD" filtrar '../x' < "$TMP/rutas" > /dev/null 2>&1 || rc=$?
es "un idioma raro se rechaza" '[ "$rc" = 2 ]'

# 2. "tiene": el inglés no necesita nada; los demás, su marca.
mkdir -p "$TMP/marcas"; : > "$TMP/marcas/es"
es "tiene: inglés siempre" 'LAZARO_TRADUCCIONES_MARCAS="$TMP/marcas" sh "$TRAD" tiene en_GB.UTF-8'
es "tiene: español con su marca" 'LAZARO_TRADUCCIONES_MARCAS="$TMP/marcas" sh "$TRAD" tiene es_AR.UTF-8'
es "tiene: portugués sin marca, no" '! LAZARO_TRADUCCIONES_MARCAS="$TMP/marcas" sh "$TRAD" tiene pt_BR.UTF-8'

# 3. lazaro-idioma sin ventana.
python3 "$IDIOMA" --listar > "$TMP/lista"
es "lista: español de Colombia, España, inglés y portugués" 'grep -q "^idioma	es_CO.UTF-8	" "$TMP/lista" && grep -q "^idioma	es_ES.UTF-8	" "$TMP/lista" && grep -q "^idioma	en_US.UTF-8	" "$TMP/lista" && grep -q "^idioma	pt_BR.UTF-8	" "$TMP/lista"'
es "lista: teclado latinoamericano y español" 'grep -q "^teclado	latam	" "$TMP/lista" && grep -q "^teclado	es	" "$TMP/lista"'
# Cada teclado sugerido por un idioma está en la lista de teclados.
faltan=$(awk -F '\t' '$1 == "teclado" { t[$2] = 1 } $1 == "idioma" { s[$4] = 1 }
	END { for (k in s) if (!(k in t)) print k }' "$TMP/lista")
es "cada idioma sugiere un teclado de la lista" '[ -z "$faltan" ]'
R="$TMP/raiz"
LAZARO_IDIOMA_RAIZ="$R" python3 "$IDIOMA" --guardar pt_BR.UTF-8 br
es "guardar: idioma en profile.d" 'grep -qx "export LANG=pt_BR.UTF-8" "$R/etc/profile.d/00-idioma.sh"'
es "guardar: teclado para Xorg (y el instalador)" 'grep -q "\"XkbLayout\" \"br\"" "$R/etc/X11/xorg.conf.d/00-keyboard.conf" && ! grep -q XkbVariant "$R/etc/X11/xorg.conf.d/00-keyboard.conf"'
LAZARO_IDIOMA_RAIZ="$R" python3 "$IDIOMA" --guardar - us intl
es "guardar solo el teclado deja el idioma" 'grep -qx "export LANG=pt_BR.UTF-8" "$R/etc/profile.d/00-idioma.sh" && grep -q "\"XkbVariant\" \"intl\"" "$R/etc/X11/xorg.conf.d/00-keyboard.conf"'
rc=0; LAZARO_IDIOMA_RAIZ="$R" python3 "$IDIOMA" --guardar 'es_CO.UTF-8; rm -rf /' - 2>/dev/null || rc=$?
es "guardar: un idioma que no está en la lista se rechaza" '[ "$rc" = 2 ] && grep -qx "export LANG=pt_BR.UTF-8" "$R/etc/profile.d/00-idioma.sh"'
rc=0; LAZARO_IDIOMA_RAIZ="$R" python3 "$IDIOMA" --guardar - 'us"' 2>/dev/null || rc=$?
es "guardar: un teclado que no está en la lista se rechaza" '[ "$rc" = 2 ]'
es "la live arranca en español" 'grep -qx "export LANG=es_CO.UTF-8" "$DIR/live/etc/profile.d/00-idioma.sh"'
es "el idioma de la live es el predeterminado de lazaro-idioma" 'LAZARO_IDIOMA_RAIZ="$DIR/live" LANG=C python3 "$IDIOMA" --listar | grep -q "^idioma	es_CO.UTF-8	.*	actual$"'

# 4. El botón de la Bienvenida: en la sesión de prueba, no en el instalado.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\n' > "$TMP/bin/lazaro-idioma"; chmod +x "$TMP/bin/lazaro-idioma"
ln -s "$(command -v python3)" "$TMP/bin/python3"
for d in live instalado; do
	LAZARO_BIENVENIDA_SOLO_PATH=1 LAZARO_BIENVENIDA_DIR="$DIR/live/usr/share/lazaro/bienvenida" \
		LAZARO_BIENVENIDA_DONDE=$d PATH="$TMP/bin" python3 "$DIR/live/usr/sbin/lazaro-bienvenida" --listar > "$TMP/b-$d"
done
es "Bienvenida (live): se ve Idioma y teclado" 'grep -q "	Idioma y teclado · Language	visible	lazaro-idioma$" "$TMP/b-live"'
es "Bienvenida (instalado): no se ve" 'grep -q "	Idioma y teclado · Language	oculta	" "$TMP/b-instalado"'

# 5. Con apk (Alpine): un paquete -lang de verdad.
if command -v apk >/dev/null 2>&1 && apk search -q -x xfce4-panel-lang 2>/dev/null | grep -q .; then
	sh "$TRAD" extraer "$TMP/destino" es xfce4-panel-lang > "$TMP/extraer.log" 2>&1 || cat "$TMP/extraer.log" >&2
	es "apk: xfce4-panel en español" '[ -s "$TMP/destino/usr/share/locale/es/LC_MESSAGES/xfce4-panel.mo" ]'
	es "apk: sin otros idiomas" '[ -z "$(find "$TMP/destino/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name "es*")" ]'
	es "apk: deja la marca del español" '[ -e "$TMP/destino/usr/share/lazaro/traducciones/es" ]'
	echo "     (español de xfce4-panel: $(du -sk "$TMP/destino" | cut -f1) KB)"
else
	echo "     (sin apk: se salta la descarga de un paquete -lang de verdad)"
fi

echo
if [ "$fallos" -gt 0 ]; then
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
echo "Las $n pruebas pasaron."
