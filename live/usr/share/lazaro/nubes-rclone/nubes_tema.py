#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lázaro Nubes con los colores y la letra del escritorio.

Tkinter no lee el tema del escritorio: por eso la ventana se veía igual
(gris) en todos. Este módulo le pregunta a GTK 3 (el mismo que usa la
Bienvenida) qué colores, letra y tamaño usa el escritorio, claro u
oscuro, y se los pone a las ventanas de Tkinter (estilo "clam" de ttk y
los widgets clásicos de tk).

GTK se consulta en un proceso aparte: así no se mezcla con Tkinter en
el mismo programa y, si falla (sin GTK, sin pantalla, poca memoria), la
aplicación sigue con su aspecto de siempre.

Uso (nubes_rclone.py):
    import nubes_tema as nt
    nt.aplicar(ventana, ttk.Style(ventana))
    ... font=(nt.FAMILIA, 14, "bold") ...  background=nt.COLORES["base"]
"""

import json
import os
import subprocess
import sys

# Lo que usa la aplicación cuando no hay tema (o antes de aplicarlo).
FAMILIA = "TkDefaultFont"
FIJA = "TkFixedFont"
COLORES = {
    "fondo": "#dcdad5",       # ventanas
    "texto": "#000000",       # letras sobre el fondo
    "base": "#ffffff",        # campos de texto y listas
    "texto_base": "#222222",  # letras en los campos
    "seleccion": "#4a90d9",
    "texto_seleccion": "#ffffff",
    "apagado": "#555555",     # textos secundarios y desactivados
    "borde": "#9e9a91",
    "ayuda_fondo": "#ffffe0",  # globitos de ayuda
    "ayuda_texto": "#222222",
    "ok": "#1a7f37",
    "mal": "#c62828",
}
OSCURO = False

# Programa que corre aparte: imprime en JSON lo que GTK sabe del tema.
_CONSULTA = r'''
import json, sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Pango
ok, _ = Gtk.init_check(sys.argv)
if not ok:
    sys.exit(1)
ajustes = Gtk.Settings.get_default()
ventana = Gtk.Window()
caja = Gtk.Box()
ventana.add(caja)
etiqueta = Gtk.Label(label="x")
campo = Gtk.Entry()
boton = Gtk.Button(label="x")
for w in (etiqueta, campo, boton):
    caja.add(w)
ventana.realize()
caja.show_all()
def hexa(c):
    return "#%02x%02x%02x" % (round(c.red * 255), round(c.green * 255), round(c.blue * 255))
def nombrado(ctx, *nombres):
    for n in nombres:
        ok, c = ctx.lookup_color(n)
        if ok:
            return hexa(c)
    return None
cv = ventana.get_style_context()
N = Gtk.StateFlags.NORMAL
r = {
    "fondo": nombrado(cv, "theme_bg_color", "bg_color") or hexa(cv.get_background_color(N)),
    "texto": nombrado(cv, "theme_fg_color", "fg_color") or hexa(etiqueta.get_style_context().get_color(N)),
    "base": nombrado(cv, "theme_base_color", "base_color") or hexa(campo.get_style_context().get_background_color(N)),
    "texto_base": nombrado(cv, "theme_text_color", "text_color") or hexa(campo.get_style_context().get_color(N)),
    "seleccion": nombrado(cv, "theme_selected_bg_color", "selected_bg_color"),
    "texto_seleccion": nombrado(cv, "theme_selected_fg_color", "selected_fg_color"),
    "apagado": nombrado(cv, "insensitive_fg_color", "theme_unfocused_fg_color"),
    "borde": nombrado(cv, "borders", "unfocused_borders"),
    "boton": hexa(boton.get_style_context().get_background_color(N)),
    "ayuda_fondo": nombrado(cv, "tooltip_bg_color", "theme_tooltip_bg_color"),
    "ayuda_texto": nombrado(cv, "tooltip_fg_color", "theme_tooltip_fg_color"),
}
letra = Pango.FontDescription.from_string(ajustes.props.gtk_font_name or "Sans 10")
r["familia"] = letra.get_family() or "Sans"
tam = letra.get_size()
r["tamano"] = round(tam / Pango.SCALE) if tam else 10
r["tema"] = ajustes.props.gtk_theme_name or ""
r["prefiere_oscuro"] = bool(ajustes.props.gtk_application_prefer_dark_theme)
print(json.dumps({k: v for k, v in r.items() if v is not None}))
'''


def _luz(color):
    """Brillo de 0 (negro) a 1 (blanco) de un color #rrggbb."""
    try:
        r, g, b = (int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    except (ValueError, TypeError, IndexError):
        return 1.0
    return 0.299 * r + 0.587 * g + 0.114 * b


def _mezcla(a, b, t):
    """Color entre a y b (t=0 es a, t=1 es b)."""
    try:
        ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
        cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    except (ValueError, TypeError, IndexError):
        return a
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(ca, cb))


def _transparente(color):
    # GTK devuelve negro puro cuando el fondo es una imagen o un degradado
    # (no un color): no sirve como fondo.
    return not color or color == "#000000"


def leer_tema():
    """Lo que GTK dice del tema del escritorio, o None si no se pudo."""
    if os.environ.get("NUBES_SIN_TEMA"):
        return None
    try:
        salida = subprocess.run([sys.executable, "-c", _CONSULTA], capture_output=True,
                                text=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return None
    if salida.returncode != 0:
        return None
    try:
        datos = json.loads(salida.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None
    return datos if isinstance(datos, dict) and datos.get("fondo") else None


def aplicar(raiz, estilo):
    """Pone los colores y la letra del escritorio. Devuelve True si pudo."""
    global FAMILIA, OSCURO
    datos = leer_tema()
    if not datos:
        return False
    c = dict(COLORES)
    for k in ("fondo", "texto", "base", "texto_base", "seleccion", "texto_seleccion",
              "apagado", "borde", "ayuda_fondo", "ayuda_texto"):
        if not _transparente(datos.get(k)):
            c[k] = datos[k]
    OSCURO = _luz(c["fondo"]) < 0.5
    if _transparente(datos.get("apagado")):
        c["apagado"] = _mezcla(c["texto"], c["fondo"], 0.4)
    if _transparente(datos.get("borde")):
        c["borde"] = _mezcla(c["fondo"], c["texto"], 0.3)
    if _transparente(datos.get("ayuda_fondo")) or _transparente(datos.get("ayuda_texto")):
        c["ayuda_fondo"], c["ayuda_texto"] = c["base"], c["texto_base"]
    boton = datos.get("boton")
    if _transparente(boton) or boton == c["fondo"]:
        boton = _mezcla(c["fondo"], c["base"], 0.5 if not OSCURO else 0.0)
        if boton == c["fondo"]:
            boton = _mezcla(c["fondo"], c["texto"], 0.08)
    c["boton"] = boton
    c["boton_encima"] = _mezcla(boton, c["texto"], 0.08)
    c["pestana"] = _mezcla(c["fondo"], c["texto"], 0.07)
    if OSCURO:
        c["ok"], c["mal"] = "#57c46a", "#ff7070"
    COLORES.update(c)

    # --- Letra: la del escritorio, en todos los tipos de letra de Tk ---
    try:
        from tkinter import font as tkfont
        familia = datos.get("familia")
        tamano = int(datos.get("tamano") or 10)
        if familia and familia.lower() in {f.lower() for f in tkfont.families(raiz)}:
            FAMILIA = familia
        for nombre in ("TkDefaultFont", "TkTextFont", "TkMenuFont", "TkHeadingFont",
                       "TkCaptionFont", "TkIconFont", "TkTooltipFont", "TkSmallCaptionFont"):
            try:
                f = tkfont.nametofont(nombre, root=raiz)
            except Exception:
                continue
            cambios = {"size": tamano - 1 if nombre == "TkSmallCaptionFont" else tamano}
            if FAMILIA != "TkDefaultFont":
                cambios["family"] = FAMILIA
            f.configure(**cambios)
        try:
            tkfont.nametofont("TkFixedFont", root=raiz).configure(size=tamano)
        except Exception:
            pass
    except Exception:
        pass

    # --- ttk (estilo clam): todos los controles ---
    estilo.configure(".", background=c["fondo"], foreground=c["texto"],
                     fieldbackground=c["base"], insertcolor=c["texto_base"],
                     selectbackground=c["seleccion"], selectforeground=c["texto_seleccion"],
                     troughcolor=_mezcla(c["fondo"], c["texto"], 0.1),
                     bordercolor=c["borde"], lightcolor=c["fondo"], darkcolor=c["borde"],
                     focuscolor=c["seleccion"], arrowcolor=c["texto"])
    estilo.map(".", foreground=[("disabled", c["apagado"])],
               background=[("disabled", c["fondo"])])
    estilo.configure("TButton", background=c["boton"], foreground=c["texto"],
                     lightcolor=c["boton"], darkcolor=c["borde"], padding=(10, 4))
    estilo.map("TButton", background=[("disabled", c["fondo"]), ("pressed", c["pestana"]),
                                      ("active", c["boton_encima"])],
               lightcolor=[("active", c["boton_encima"])])
    estilo.configure("Acento.TButton", background=c["seleccion"],
                     foreground=c["texto_seleccion"], lightcolor=c["seleccion"])
    estilo.map("Acento.TButton",
               background=[("disabled", c["fondo"]),
                           ("active", _mezcla(c["seleccion"], c["texto_seleccion"], 0.12))],
               foreground=[("disabled", c["apagado"])])
    estilo.configure("TNotebook", background=c["fondo"], bordercolor=c["borde"])
    estilo.configure("TNotebook.Tab", background=c["pestana"], foreground=c["texto"],
                     lightcolor=c["pestana"], bordercolor=c["borde"])
    estilo.map("TNotebook.Tab", background=[("selected", c["fondo"])],
               lightcolor=[("selected", c["fondo"])],
               foreground=[("selected", c["texto"])])
    for campo in ("TEntry", "TCombobox", "TSpinbox"):
        estilo.configure(campo, fieldbackground=c["base"], foreground=c["texto_base"],
                         background=c["boton"])
        estilo.map(campo, fieldbackground=[("readonly", c["base"]), ("disabled", c["fondo"])],
                   foreground=[("readonly", c["texto_base"]), ("disabled", c["apagado"])],
                   selectbackground=[("readonly", c["base"])],
                   selectforeground=[("readonly", c["texto_base"])])
    for marca in ("TCheckbutton", "TRadiobutton"):
        estilo.configure(marca, indicatorbackground=c["base"], indicatorforeground=c["texto_base"])
        estilo.map(marca, background=[("active", c["fondo"])],
                   indicatorbackground=[("disabled", c["fondo"]), ("pressed", c["pestana"])])
    estilo.configure("Treeview", background=c["base"], fieldbackground=c["base"],
                     foreground=c["texto_base"])
    estilo.map("Treeview", background=[("selected", c["seleccion"])],
               foreground=[("selected", c["texto_seleccion"])])
    estilo.configure("Treeview.Heading", background=c["boton"], foreground=c["texto"])
    estilo.configure("TLabelframe.Label", foreground=c["texto"])
    estilo.configure("Horizontal.TProgressbar", background=c["seleccion"])
    estilo.configure("Ok.TLabel", foreground=c["ok"])
    estilo.configure("Mal.TLabel", foreground=c["mal"])

    # --- tk clásico (texto, listas, menús, la lista de los combos) ---
    for patron, valor in (
            ("*Background", c["fondo"]), ("*Foreground", c["texto"]),
            ("*Text.background", c["base"]), ("*Text.foreground", c["texto_base"]),
            ("*Text.insertBackground", c["texto_base"]),
            ("*Listbox.background", c["base"]), ("*Listbox.foreground", c["texto_base"]),
            ("*selectBackground", c["seleccion"]), ("*selectForeground", c["texto_seleccion"]),
            ("*Menu.background", c["base"]), ("*Menu.foreground", c["texto_base"]),
            ("*Menu.activeBackground", c["seleccion"]),
            ("*Menu.activeForeground", c["texto_seleccion"]),
            ("*TCombobox*Listbox.background", c["base"]),
            ("*TCombobox*Listbox.foreground", c["texto_base"]),
            ("*TCombobox*Listbox.selectBackground", c["seleccion"]),
            ("*TCombobox*Listbox.selectForeground", c["texto_seleccion"])):
        raiz.option_add(patron, valor)
    try:
        raiz.configure(background=c["fondo"])
    except Exception:
        pass
    return True
