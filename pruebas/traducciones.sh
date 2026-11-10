#!/bin/sh
# Prueba las traducciones de las herramientas de Lázaro (inglés y
# portugués de Brasil) sin abrir ventanas:
#   - que traducciones/lazaro.pot esté al día y que cada idiomas/*.po
#     tenga todos los textos traducidos, con los mismos %s;
#   - que texto.sh (programas de shell) y lazaro_texto.py (Python) elijan
#     el archivo según el idioma de la sesión y den la misma traducción;
#   - que la Bienvenida salga traducida.
#
#   pruebas/traducciones.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
export LAZARO_TEXTO_DIR="$DIR/live/usr/share/lazaro"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Sin restos de Python (__pycache__) en el repositorio.
export PYTHONDONTWRITEBYTECODE=1

fallos=0
n=0
ok() { n=$((n + 1)); printf "ok   %s %s\n" "$n" "$1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); printf "FALLO %s %s\n" "$n" "$1" >&2; }
igual() { # NOMBRE OBTENIDO ESPERADO
	if [ "$2" = "$3" ]; then ok "$1"; else mal "$1: salió [$2], se esperaba [$3]"; fi
}

# 1. Plantilla al día y traducciones completas.
if python3 "$DIR/traducciones/extraer.py" --revisar >"$TMP/revisar" 2>&1; then
	ok "lazaro.pot al día y traducciones completas"
else
	mal "traducciones incompletas o plantilla vieja:"
	cat "$TMP/revisar" >&2
fi

# 2. texto.sh según el idioma de la sesión.
sh_texto() { # LANG TEXTO
	LANG="$1" LC_ALL="" LC_MESSAGES="" sh -c '. "$LAZARO_TEXTO_DIR/texto.sh"; _ "$1"' sh "$2"
}
igual "shell, inglés" "$(sh_texto en_US.UTF-8 Cerrar)" Close
igual "shell, portugués de Brasil" "$(sh_texto pt_BR.UTF-8 Cerrar)" Fechar
igual "shell, portugués de Portugal usa pt_BR" "$(sh_texto pt_PT.UTF-8 Cerrar)" Fechar
igual "shell, idioma sin archivo usa inglés" "$(sh_texto fr_FR.UTF-8 Cerrar)" Close
igual "shell, español queda igual" "$(sh_texto es_CO.UTF-8 Cerrar)" Cerrar
igual "shell, sin idioma queda en español" "$(sh_texto C Cerrar)" Cerrar
igual "shell, texto desconocido queda igual" "$(sh_texto en_US.UTF-8 'No existe')" "No existe"
igual "shell, \\n es salto de línea (español)" "$(sh_texto es_CO 'a\nb')" "a
b"
igual "shell, %s con printf" \
	"$(LANG=en_US.UTF-8 sh -c '. "$LAZARO_TEXTO_DIR/texto.sh"; printf "$(_ "Versión %s")" 0.2')" "Version 0.2"
igual "shell, LC_ALL manda sobre LANG" \
	"$(LANG=es_CO.UTF-8 LC_ALL=pt_BR.UTF-8 sh -c '. "$LAZARO_TEXTO_DIR/texto.sh"; _ Cerrar')" Fechar

# 3. lazaro_texto.py igual.
py_texto() { # LANG TEXTO
	LANG="$1" LC_ALL="" LC_MESSAGES="" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from lazaro_texto import _
sys.stdout.write(_(sys.argv[2]))' "$LAZARO_TEXTO_DIR" "$2"
}
igual "python, inglés" "$(py_texto en_US.UTF-8 Cerrar)" Close
igual "python, portugués de Brasil" "$(py_texto pt_BR.UTF-8 Cerrar)" Fechar
igual "python, idioma sin archivo usa inglés" "$(py_texto de_DE.UTF-8 Cerrar)" Close
igual "python, español queda igual" "$(py_texto es_ES.UTF-8 Cerrar)" Cerrar

# 4. Shell y Python leen igual cada texto de cada .po (comillas, saltos de
# línea y textos largos en varias líneas).
for po in "$LAZARO_TEXTO_DIR"/idiomas/*.po; do
	idioma="$(basename "$po" .po)"
	python3 - "$DIR" "$idioma" "$TMP/$idioma" <<-'PY'
		import os, sys
		sys.path.insert(0, os.path.join(sys.argv[1], "traducciones"))
		# Por la función de los programas, con el idioma de la sesión.
		os.environ["LANG"] = sys.argv[2] + ".UTF-8"
		for v in ("LC_ALL", "LC_MESSAGES"):
		    os.environ.pop(v, None)
		import extraer
		from lazaro_texto import _
		os.makedirs(sys.argv[3])
		for i, (t, _r) in enumerate(extraer.todos()):
		    with open(os.path.join(sys.argv[3], "%03d.id" % i), "w", encoding="utf-8") as f:
		        f.write(t)
		    with open(os.path.join(sys.argv[3], "%03d.py" % i), "w", encoding="utf-8") as f:
		        f.write(_(t))
	PY
	distintos=0
	for id in "$TMP/$idioma"/*.id; do
		# El texto como lo escribe el programa: los saltos de línea como \n.
		clave="$(awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }' "$id")"
		LANG="$idioma.UTF-8" sh -c '. "$LAZARO_TEXTO_DIR/texto.sh"; _ "$1"' sh "$clave" > "${id%.id}.sh"
		if ! cmp -s "${id%.id}.sh" "${id%.id}.py"; then
			distintos=$((distintos + 1))
			[ "$distintos" -gt 3 ] || echo "  distinto: $(head -c 70 "$id")" >&2
		fi
	done
	if [ "$distintos" -eq 0 ]; then
		ok "$idioma: shell y Python dan la misma traducción en los $(ls "$TMP/$idioma"/*.id | wc -l) textos"
	else
		mal "$idioma: $distintos textos salen distintos en shell y en Python"
	fi
done

# 5. La Bienvenida en inglés y en portugués.
bienvenida() { # LANG
	LANG="$1" LAZARO_BIENVENIDA_DIR="$LAZARO_TEXTO_DIR/bienvenida" LAZARO_BIENVENIDA_DONDE=live \
		python3 "$DIR/live/usr/sbin/lazaro-bienvenida" --listar 2>/dev/null || true
}
if bienvenida en_US.UTF-8 | grep -q 'Getting started'; then
	ok "Bienvenida en inglés"
else
	mal "Bienvenida en inglés: no aparece 'Getting started'"
fi
if bienvenida pt_BR.UTF-8 | grep -q 'Primeiros passos'; then
	ok "Bienvenida en portugués"
else
	mal "Bienvenida en portugués: no aparece 'Primeiros passos'"
fi
if bienvenida es_CO.UTF-8 | grep -q 'Primeros pasos'; then
	ok "Bienvenida en español"
else
	mal "Bienvenida en español: no aparece 'Primeros pasos'"
fi

# 6. Los menús (.desktop) de Lázaro tienen nombre en inglés y portugués.
for f in "$DIR"/live/usr/share/applications/lazaro-*.desktop "$DIR"/live/etc/xdg/autostart/lazaro-*.desktop \
	"$DIR"/live/usr/share/lazaro/lazaro-*.desktop; do
	for i in en pt_BR; do
		# Con texto: un nombre vacío deja el menú en blanco.
		grep -q "^Name\[$i\]=." "$f" || mal "$(basename "$f"): falta Name[$i]"
	done
done
ok "menús con nombre en inglés y portugués"

echo
if [ "$fallos" -gt 0 ]; then
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
echo "Las $n pruebas pasaron."
