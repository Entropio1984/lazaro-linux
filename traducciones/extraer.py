#!/usr/bin/env python3
"""Textos de las herramientas de Lázaro para traducir.

Junta los textos marcados para traducir y los deja en
traducciones/lazaro.pot (la plantilla, formato gettext):

  - programas de shell de live/usr/sbin:  $(_ 'texto')  y  _ 'texto'
  - programas de Python de live/usr/sbin: _("texto")
  - Bienvenida: Nombre, Descripcion, Seccion y Boton de cada
    bienvenida/funciones/*.conf, y los párrafos de bienvenida/portada.txt

Uso:
  python3 traducciones/extraer.py            escribe lazaro.pot
  python3 traducciones/extraer.py --revisar  comprueba que lazaro.pot esté
      al día y que cada idiomas/*.po tenga todos los textos traducidos, con
      los mismos %s que el original (si no, termina con error)
  python3 traducciones/extraer.py --actualizar
      escribe lazaro.pot y agrega a cada .po los textos nuevos (vacíos)
"""

import ast
import configparser
import glob
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SBIN = os.path.join(RAIZ, "live/usr/sbin")
DATOS = os.path.join(RAIZ, "live/usr/share/lazaro")
IDIOMAS = os.path.join(DATOS, "idiomas")
POT = os.path.join(RAIZ, "traducciones/lazaro.pot")

# _ 'texto' o $(_ 'texto') o $(_ Palabra), fuera de los comentarios.
SHELL = re.compile(r"(?<![\w$])_ (?:'([^']*)'|([^\s'\"()$;|&<>]+)\))")


def rel(ruta):
    return os.path.relpath(ruta, RAIZ)


def textos_shell(ruta, cod):
    salida = []
    sin_comentarios = re.sub(r"(?m)^\s*#.*$", "", cod)
    for m in SHELL.finditer(sin_comentarios):
        t = m.group(1) if m.group(1) is not None else m.group(2)
        # En el shell, "\n" escrito dentro del texto es un salto de línea.
        salida.append((t.replace("\\n", "\n"), rel(ruta)))
    return salida


def textos_python(ruta, cod):
    salida = []
    for nodo in ast.walk(ast.parse(cod, ruta)):
        if (isinstance(nodo, ast.Call) and isinstance(nodo.func, ast.Name)
                and nodo.func.id == "_" and nodo.args
                and isinstance(nodo.args[0], ast.Constant)
                and isinstance(nodo.args[0].value, str)):
            salida.append((nodo.args[0].value, rel(ruta)))
    return salida


def textos_bienvenida():
    # Botón de las funciones que no dicen el suyo (lazaro-bienvenida).
    salida = [("Abrir", "live/usr/sbin/lazaro-bienvenida")]
    for ruta in sorted(glob.glob(os.path.join(DATOS, "bienvenida/funciones/*.conf"))):
        cp = configparser.ConfigParser(interpolation=None)
        with open(ruta, encoding="utf-8") as f:
            cp.read_file(f)
        d = cp["Funcion"]
        for clave in ("nombre", "seccion", "boton"):
            if d.get(clave, "").strip():
                salida.append((d[clave].strip(), rel(ruta)))
        salida.append((" ".join(d["descripcion"].split()), rel(ruta)))
    ruta = os.path.join(DATOS, "bienvenida/portada.txt")
    with open(ruta, encoding="utf-8") as f:
        for b in f.read().split("\n\n"):
            b = " ".join(b.split())
            if b:
                salida.append((b, rel(ruta)))
    return salida


def todos():
    """[(texto, [archivos])] en el orden en que aparecen."""
    lista = []
    for ruta in sorted(glob.glob(os.path.join(SBIN, "*"))):
        # Solo programas: otras pruebas pueden dejar __pycache__ aquí.
        if not os.path.isfile(ruta):
            continue
        with open(ruta, encoding="utf-8") as f:
            cod = f.read()
        if cod.startswith("#!/usr/bin/env python3") or cod.startswith("#!/usr/bin/python3"):
            lista += textos_python(ruta, cod)
        else:
            lista += textos_shell(ruta, cod)
    lista += textos_bienvenida()
    orden, donde = [], {}
    for t, r in lista:
        if not t.strip():
            continue
        if t not in donde:
            orden.append(t)
            donde[t] = []
        if r not in donde[t]:
            donde[t].append(r)
    return [(t, donde[t]) for t in orden]


def po_cadena(t):
    t = t.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
    partes = t.split("\n")
    if len(partes) == 1:
        return '"%s"' % t
    lineas = [p + "\\n" for p in partes[:-1]] + ([partes[-1]] if partes[-1] else [])
    return '""\n' + "\n".join('"%s"' % l for l in lineas)


CABECERA = '''# Textos de las herramientas de Lázaro Linux.
# Plantilla generada por traducciones/extraer.py: no editar a mano.
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"
'''


def plantilla():
    partes = [CABECERA]
    for t, rutas in todos():
        partes.append("#: %s\nmsgid %s\nmsgstr \"\"\n" % (" ".join(rutas), po_cadena(t)))
    return "\n".join(partes)


sys.path.insert(0, DATOS)
from lazaro_texto import leer_po  # noqa: E402


def marcas(t):
    # En orden: los datos se ponen por posición.
    return re.findall(r"%[sd%]", t)


def revisar():
    errores = []
    try:
        with open(POT, encoding="utf-8") as f:
            if f.read() != plantilla():
                errores.append("lazaro.pot no está al día: corre python3 traducciones/extraer.py --actualizar")
    except OSError:
        errores.append("falta traducciones/lazaro.pot")
    textos = [t for t, _r in todos()]
    pos = sorted(glob.glob(os.path.join(IDIOMAS, "*.po")))
    if not pos:
        errores.append("no hay archivos en %s" % rel(IDIOMAS))
    for po in pos:
        tabla = leer_po(po)
        n = os.path.basename(po)
        for t in textos:
            if t not in tabla:
                errores.append("%s: falta traducir: %r" % (n, t[:70]))
            elif marcas(t) != marcas(tabla[t]):
                errores.append("%s: los %%s no coinciden: %r" % (n, t[:70]))
        for t in tabla:
            if t and t not in textos:
                errores.append("%s: texto que ya no existe (borrarlo): %r" % (n, t[:70]))
        print("%s: %d de %d textos traducidos" % (n, sum(1 for t in textos if t in tabla), len(textos)))
    for e in errores:
        print("ERROR " + e)
    return not errores


def actualizar():
    with open(POT, "w", encoding="utf-8") as f:
        f.write(plantilla())
    for po in sorted(glob.glob(os.path.join(IDIOMAS, "*.po"))):
        with open(po, encoding="utf-8") as f:
            cod = f.read()
        hay = set(leer_po_todo(po))
        nuevos = [t for t, _r in todos() if t not in hay]
        if nuevos:
            with open(po, "a", encoding="utf-8") as f:
                for t in nuevos:
                    f.write("\nmsgid %s\nmsgstr \"\"\n" % po_cadena(t))
            print("%s: %d textos nuevos para traducir" % (os.path.basename(po), len(nuevos)))
        del cod


def leer_po_todo(ruta):
    """Todos los msgid del archivo, traducidos o no."""
    ids, actual, en_id = [], None, False
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.startswith("msgid "):
                actual, en_id = linea[6:].strip()[1:-1], True
            elif linea.startswith('"') and en_id:
                actual += linea.strip()[1:-1]
            else:
                if en_id and actual is not None:
                    ids.append(actual)
                en_id = False
    from lazaro_texto import _sin_escapes
    return [_sin_escapes(i) for i in ids]


if __name__ == "__main__":
    if "--revisar" in sys.argv[1:]:
        sys.exit(0 if revisar() else 1)
    elif "--actualizar" in sys.argv[1:]:
        actualizar()
    else:
        with open(POT, "w", encoding="utf-8") as f:
            f.write(plantilla())
        print("%s: %d textos" % (rel(POT), len(todos())))
