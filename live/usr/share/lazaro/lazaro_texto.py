# Traducción de los textos de las herramientas de Lázaro (programas de
# Python). Los textos se escriben en español; las traducciones están en
# idiomas/<idioma>.po, los mismos archivos que usan los programas de shell
# (texto.sh). Uso:
#
#   sys.path.insert(0, os.environ.get("LAZARO_TEXTO_DIR", "/usr/share/lazaro"))
#   try:
#       from lazaro_texto import _
#   except ImportError:
#       def _(texto): return texto
#
# Si el idioma de la sesión es español, o no hay archivo, sale el texto
# tal cual. Un idioma sin archivo propio usa el inglés.

import glob
import os

DIR = os.path.join(os.environ.get("LAZARO_TEXTO_DIR", "/usr/share/lazaro"), "idiomas")


def idioma_de_la_sesion():
    for v in ("LC_ALL", "LC_MESSAGES", "LANG"):
        if os.environ.get(v):
            return os.environ[v].split(".")[0].split("@")[0]
    return ""


def archivo(idioma=None):
    """El .po que corresponde al idioma, o None (español)."""
    i = idioma_de_la_sesion() if idioma is None else idioma
    if i in ("", "C", "POSIX") or i == "es" or i.startswith("es_"):
        return None
    base = i.split("_")[0]
    for c in [os.path.join(DIR, i + ".po"), os.path.join(DIR, base + ".po")] \
            + sorted(glob.glob(os.path.join(DIR, base + "_*.po"))) + [os.path.join(DIR, "en.po")]:
        if os.path.isfile(c):
            return c
    return None


def _sin_escapes(s):
    r, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            i += 1
            c = {"n": "\n", "t": "\t"}.get(s[i], s[i])
        r.append(c)
        i += 1
    return "".join(r)


def leer_po(ruta):
    """{texto original: traducción} de un archivo .po (solo lo traducido)."""
    tabla, estado, msgid, msgstr = {}, None, "", ""

    def cerrar():
        if estado == "str" and msgid and msgstr:
            tabla[msgid] = msgstr

    def cadena(linea):
        linea = linea.strip()
        return _sin_escapes(linea[linea.index('"') + 1:linea.rindex('"')])

    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.startswith("msgid "):
                cerrar()
                estado, msgid, msgstr = "id", cadena(linea), ""
            elif linea.startswith("msgstr "):
                estado, msgstr = "str", cadena(linea)
            elif linea.startswith('"'):
                if estado == "id":
                    msgid += cadena(linea)
                elif estado == "str":
                    msgstr += cadena(linea)
            elif not linea.strip() or linea.startswith("#"):
                cerrar()
                estado = None
    cerrar()
    return tabla


_TABLA = None


def _(texto):
    global _TABLA
    if _TABLA is None:
        _TABLA = {}
        ruta = archivo()
        if ruta:
            try:
                _TABLA = leer_po(ruta)
            except (OSError, UnicodeError, ValueError):
                _TABLA = {}
    return _TABLA.get(texto, texto)
