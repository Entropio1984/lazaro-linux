#!/usr/bin/env python3
"""Dibuja las imágenes del tema Lázaro: los fondos de pantalla y el
ícono del menú (el pulso).

Las imágenes quedan guardadas en el repositorio, así que compilar la ISO
no necesita Python ni Pillow: este programa solo se corre para cambiar
los dibujos:

    python3 tema/generar-imagenes.py

Colores (los del logo): azul noche del fondo, celeste del pulso, azul de
las montañas y amarillo del sol.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

AQUI = os.path.dirname(os.path.abspath(__file__))
FONDOS = os.path.join(AQUI, "usr", "share", "backgrounds", "lazaro")
ICONOS = os.path.join(AQUI, "usr", "share", "icons", "Lazaro")

NOCHE = (6, 24, 44)
NOCHE_CLARA = (16, 52, 88)
CELESTE = (41, 182, 246)
AZUL = (37, 99, 196)
SOL = (246, 195, 68)

ANCHO, ALTO = 1920, 1200


def latido(x):
    """Altura del latido (de -1 a 1) en x (0..1): línea plana con un
    complejo PQRST cerca del centro, como en el logo y el arranque."""
    def campana(centro, ancho, alto):
        return alto * math.exp(-((x - centro) / ancho) ** 2)
    return (campana(0.38, 0.025, 0.12) + campana(0.47, 0.008, -0.18)
            + campana(0.50, 0.010, 1.00) + campana(0.53, 0.010, -0.35)
            + campana(0.64, 0.040, 0.22))


def degradado(arriba, abajo, ancho=ANCHO, alto=ALTO):
    img = Image.new("RGB", (ancho, alto))
    d = ImageDraw.Draw(img)
    for y in range(alto):
        t = y / (alto - 1)
        d.line([(0, y), (ancho, y)], fill=tuple(
            int(a + (b - a) * t) for a, b in zip(arriba, abajo)))
    return img


def luz(img, cx, cy, radio, color, fuerza):
    """Mancha de luz suave (radial) sumada a la imagen."""
    capa = Image.new("L", img.size, 0)
    ImageDraw.Draw(capa).ellipse([cx - radio, cy - radio, cx + radio, cy + radio],
                                 fill=int(255 * fuerza))
    capa = capa.filter(ImageFilter.GaussianBlur(radio / 2))
    return Image.composite(Image.new("RGB", img.size, color), img, capa)


def linea_pulso(img, y0, amplitud, x0, x1, color, grosor, brillo=1.0,
                centro=0.5, halos=3):
    """Dibuja la línea del pulso con su resplandor."""
    capa = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(capa)
    pasos = 1600
    pts = []
    for i in range(pasos + 1):
        t = i / pasos
        x = x0 + (x1 - x0) * t
        # El latido se corre para que caiga en "centro".
        y = y0 - latido(t - centro + 0.5) * amplitud
        pts.append((x, y))
    # Se apaga hacia los bordes.
    for i in range(pasos):
        t = i / pasos
        a = min(1.0, min(t, 1 - t) * 6) * brillo
        d.line([pts[i], pts[i + 1]], fill=color + (int(255 * a),), width=grosor)
    ancho = capa.filter(ImageFilter.GaussianBlur(grosor * 7))
    resplandor = capa.filter(ImageFilter.GaussianBlur(grosor * 3))
    cerca = capa.filter(ImageFilter.GaussianBlur(grosor * 1.2))
    base = img.convert("RGBA")
    for _ in range(halos):
        base = Image.alpha_composite(base, ancho)
    base = Image.alpha_composite(base, resplandor)
    base = Image.alpha_composite(base, resplandor)
    base = Image.alpha_composite(base, cerca)
    base = Image.alpha_composite(base, capa)
    return base.convert("RGB")


def grano(img, cantidad=3):
    """Un poco de ruido para que el degradado no haga escalones."""
    # Siempre el mismo ruido (semilla fija): volver a correr el programa
    # da las mismas imágenes y git no ve cambios donde no los hay.
    azar = random.Random(1)
    lado = 256
    teja = Image.new("L", (lado, lado))
    teja.putdata([int(azar.gauss(128, 18)) for _ in range(lado * lado)])
    ruido = Image.new("L", img.size)
    for x in range(0, img.size[0], lado):
        for y in range(0, img.size[1], lado):
            ruido.paste(teja, (x, y))
    return Image.blend(img, ruido.convert("RGB"), cantidad / 100)


def fondo_pulso():
    img = degradado((8, 30, 54), (4, 14, 28))
    img = luz(img, ANCHO * 0.5, ALTO * 0.55, 700, NOCHE_CLARA, 0.55)
    # Cuadrícula de monitor, muy tenue.
    d = ImageDraw.Draw(img, "RGBA")
    for x in range(0, ANCHO, 60):
        d.line([(x, 0), (x, ALTO)], fill=CELESTE + (10,), width=1)
    for y in range(0, ALTO, 60):
        d.line([(0, y), (ANCHO, y)], fill=CELESTE + (10,), width=1)
    img = linea_pulso(img, ALTO * 0.58, 230, -40, ANCHO + 40, CELESTE, 5, centro=0.62)
    return grano(img)


def montana(d, cx, base, ancho, alto, cara, sombra, nieve=None):
    """Montaña de dos caras, como las del logo: la izquierda con luz y la
    derecha en sombra; con un poco de nieve si se pide."""
    cima = (cx, base - alto)
    d.polygon([(cx - ancho / 2, base), cima, (cx, base)], fill=cara)
    d.polygon([(cx, base), cima, (cx + ancho / 2, base)], fill=sombra)
    if nieve:
        f = 0.22
        d.polygon([cima, (cx - ancho / 2 * f, base - alto * (1 - f)),
                   (cx - ancho * 0.04, base - alto * (1 - f * 0.7)),
                   (cx + ancho * 0.03, base - alto * (1 - f * 1.1)),
                   (cx + ancho / 2 * f, base - alto * (1 - f))], fill=nieve)


def fondo_amanecer():
    img = degradado((5, 16, 32), (24, 62, 104))
    # Estrellas arriba.
    random.seed(7)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(260):
        x, y = random.uniform(0, ANCHO), random.uniform(0, ALTO * 0.45)
        r = random.choice((0.6, 0.8, 1.0, 1.4))
        a = int(random.uniform(60, 200) * (1 - y / (ALTO * 0.5)))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    # Sol que asoma detrás de las montañas, con su resplandor.
    img = luz(img, ANCHO * 0.5, ALTO * 0.62, 620, (90, 90, 80), 0.45)
    cx, cy, r = ANCHO * 0.5, ALTO * 0.60, 250
    sol = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sol).ellipse([cx - r, cy - r, cx + r, cy + r], fill=SOL + (255,))
    halo = sol.filter(ImageFilter.GaussianBlur(50))
    img = Image.alpha_composite(img.convert("RGBA"), halo)
    img = Image.alpha_composite(img, sol).convert("RGB")
    d = ImageDraw.Draw(img)
    base = ALTO * 0.86
    # Atrás: montañas grandes y claras; adelante: más bajas y oscuras.
    for cx, ancho, alto in ((ANCHO * 0.30, 900, 470), (ANCHO * 0.74, 980, 520)):
        montana(d, cx, base, ancho, alto, (52, 120, 214), (30, 82, 170), (210, 228, 250))
    for cx, ancho, alto in ((ANCHO * 0.06, 700, 300), (ANCHO * 0.52, 760, 330),
                            (ANCHO * 0.96, 700, 290)):
        montana(d, cx, base, ancho, alto, (30, 82, 168), (18, 54, 120))
    for cx, ancho, alto in ((ANCHO * 0.20, 620, 170), (ANCHO * 0.40, 560, 140),
                            (ANCHO * 0.66, 640, 180), (ANCHO * 0.88, 600, 150)):
        montana(d, cx, base, ancho, alto, (16, 48, 98), (10, 34, 72))
    d.rectangle([0, base, ANCHO, ALTO], fill=(6, 20, 38))
    img = linea_pulso(img, base + 2, 130, -40, ANCHO + 40, CELESTE, 5, centro=0.62)
    return grano(img)


def fondo_claro():
    img = degradado((236, 243, 250), (205, 222, 240))
    img = luz(img, ANCHO * 0.75, ALTO * 0.25, 600, (255, 255, 255), 0.6)
    img = linea_pulso(img, ALTO * 0.62, 210, -40, ANCHO + 40, (30, 136, 229), 5,
                      brillo=0.8, centro=0.58, halos=0)
    return grano(img, 2)


def icono_svg():
    """Ícono del menú: círculo azul noche, aro celeste y el pulso."""
    pts = []
    for i in range(121):
        t = i / 120
        x = 13 + 38 * t
        y = 34 - latido(t * 0.9 + 0.05) * 15
        pts.append(f"{x:.2f},{y:.2f}")
    camino = "M" + " L".join(pts)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <!-- Ícono del menú de Lázaro (lo dibuja tema/generar-imagenes.py) -->
  <defs>
    <radialGradient id="fondo" cx="0.5" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#174a7c"/>
      <stop offset="1" stop-color="#071a30"/>
    </radialGradient>
    <filter id="brillo" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="1.6"/>
    </filter>
  </defs>
  <circle cx="32" cy="32" r="29" fill="url(#fondo)"/>
  <circle cx="32" cy="32" r="28" fill="none" stroke="#29b6f6" stroke-width="3"/>
  <path d="{camino}" fill="none" stroke="#29b6f6" stroke-width="5"
        stroke-linejoin="round" stroke-linecap="round" filter="url(#brillo)" opacity="0.9"/>
  <path d="{camino}" fill="none" stroke="#ffffff" stroke-width="3.2"
        stroke-linejoin="round" stroke-linecap="round"/>
</svg>
"""


def icono_chico_svg(lado):
    """Para 16 a 24 píxeles el dibujo grande se ve como una cruz: aquí
    el pulso es un trazo grueso y anguloso que se lee aunque sea chico."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{lado}" height="{lado}" viewBox="0 0 16 16">
  <circle cx="8" cy="8" r="7.6" fill="#0d2c4d"/>
  <circle cx="8" cy="8" r="7" fill="none" stroke="#29b6f6" stroke-width="1.2"/>
  <path d="M2.6,8.6 H5.2 L6.6,5 L8.4,12 L9.9,6.6 L10.9,8.6 H13.4" fill="none"
        stroke="#ffffff" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>
</svg>
"""


def icono_simbolico_svg():
    """Versión de un solo color para barras que piden íconos simbólicos
    (GNOME, Plasma): el escritorio la pinta del color del texto."""
    return """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M0.8,8.6 H4.4 L6.2,3.2 L8.4,13.4 L10.2,6 L11.3,8.6 H15.2" fill="none" stroke="#bebebe"
        stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>
</svg>
"""


# Ventanas de XFCE (xfwm4): barra de título azul noche, título blanco y
# botones planos; al pasar el mouse el botón se ilumina de celeste (el
# de cerrar, de rojo).
XFWM4 = os.path.join(AQUI, "usr", "share", "themes", "Lazaro", "xfwm4")
BARRA = 32
TITULO_ACTIVO = (13, 38, 66)
TITULO_INACTIVO = (34, 52, 74)
BORDE_ACTIVO = (9, 28, 50)
BORDE_INACTIVO = (28, 44, 64)


def boton(nombre, estado, glifo):
    """Botón de 32x32 dibujado al cuádruple y achicado (bordes suaves)."""
    k = 4
    t = BARRA * k
    fondo = TITULO_INACTIVO if estado == "inactive" else TITULO_ACTIVO
    img = Image.new("RGBA", (t, t), fondo + (255,))
    d = ImageDraw.Draw(img)
    trazo = (232, 240, 250) if estado != "inactive" else (150, 168, 190)
    if estado in ("prelight", "pressed"):
        color = (232, 72, 72) if nombre == "close" else CELESTE
        if estado == "pressed":
            color = tuple(int(c * 0.75) for c in color)
        m = 5 * k
        d.ellipse([m, m, t - m, t - m], fill=color + (255,))
        trazo = (255, 255, 255)
    c = t / 2
    r = 5.5 * k
    g = int(1.7 * k)
    if glifo == "cerrar":
        d.line([(c - r, c - r), (c + r, c + r)], fill=trazo, width=g)
        d.line([(c - r, c + r), (c + r, c - r)], fill=trazo, width=g)
    elif glifo == "minimizar":
        d.line([(c - r, c + r * 0.6), (c + r, c + r * 0.6)], fill=trazo, width=g)
    elif glifo == "maximizar":
        d.rectangle([c - r, c - r, c + r, c + r], outline=trazo, width=g)
    elif glifo == "restaurar":
        q = r * 0.75
        d.rectangle([c - r + 2 * k, c - r, c + r, c + r - 2 * k], outline=trazo, width=g)
        d.rectangle([c - r, c - r + 2 * k + 1, c + q, c + r], fill=fondo + (255,) if estado not in ("prelight", "pressed") else None)
        d.rectangle([c - r, c - r + 2 * k, c + r - 2 * k, c + r], outline=trazo, width=g)
    elif glifo == "menu":
        for dy in (-r * 0.6, 0, r * 0.6):
            d.line([(c - r, c + dy), (c + r, c + dy)], fill=trazo, width=g)
    elif glifo == "enrollar":
        d.line([(c - r, c + r * 0.3), (c, c - r * 0.5), (c + r, c + r * 0.3)], fill=trazo, width=g)
    elif glifo == "desenrollar":
        d.line([(c - r, c - r * 0.3), (c, c + r * 0.5), (c + r, c - r * 0.3)], fill=trazo, width=g)
    elif glifo == "fijar":
        d.ellipse([c - r * 0.5, c - r * 0.5, c + r * 0.5, c + r * 0.5], outline=trazo, width=g)
    elif glifo == "fijado":
        d.ellipse([c - r * 0.6, c - r * 0.6, c + r * 0.6, c + r * 0.6], fill=trazo)
    return img.resize((BARRA, BARRA), Image.LANCZOS)


def tema_xfwm4():
    os.makedirs(XFWM4, exist_ok=True)
    for estado in ("active", "inactive", "prelight", "pressed"):
        for nombre, glifo in (("close", "cerrar"), ("hide", "minimizar"),
                              ("maximize", "maximizar"), ("maximize-toggled", "restaurar"),
                              ("menu", "menu"), ("shade", "enrollar"),
                              ("shade-toggled", "desenrollar"), ("stick", "fijar"),
                              ("stick-toggled", "fijado")):
            boton(nombre, estado, glifo).save(
                os.path.join(XFWM4, f"{nombre}-{estado}.png"), optimize=True)
    for estado, titulo, borde in (("active", TITULO_ACTIVO, BORDE_ACTIVO),
                                  ("inactive", TITULO_INACTIVO, BORDE_INACTIVO)):
        def pieza(nombre, ancho, alto, color):
            Image.new("RGBA", (ancho, alto), color + (255,)).save(
                os.path.join(XFWM4, f"{nombre}-{estado}.png"))
        for i in range(1, 6):
            pieza(f"title-{i}", 2, BARRA, titulo)
        pieza("top-left", 2, BARRA, titulo)
        pieza("top-right", 2, BARRA, titulo)
        for nombre in ("left", "right"):
            pieza(nombre, 2, 2, borde)
        pieza("bottom", 2, 2, borde)
        pieza("bottom-left", 2, 2, borde)
        pieza("bottom-right", 2, 2, borde)
    with open(os.path.join(XFWM4, "themerc"), "w", encoding="utf-8") as f:
        f.write("""# Ventanas de Lázaro para XFCE (las dibuja tema/generar-imagenes.py)
active_text_color=#ffffff
inactive_text_color=#a9b8ca
title_shadow_active=false
title_shadow_inactive=false
full_width_title=true
title_alignment=center
title_vertical_offset_active=0
title_vertical_offset_inactive=0
button_offset=2
button_spacing=0
show_app_icon=true
shadow_delta_height=2
shadow_delta_width=0
shadow_delta_x=0
shadow_delta_y=-6
shadow_opacity=45
frame_border_top=0
""")


def vistas_plasma():
    """Vista previa de los temas globales de Plasma: el fondo con una
    ventana de muestra (barra azul noche, contenido claro u oscuro)."""
    for variante, fondo, contenido, texto in (
            ("claro", "lazaro-amanecer.jpg", (246, 248, 251), (29, 39, 51)),
            ("oscuro", "lazaro-pulso.jpg", (15, 39, 66), (238, 244, 251))):
        destino = os.path.join(AQUI, "usr", "share", "plasma", "look-and-feel",
                               f"org.lazaro.{variante}.desktop", "contents", "previews")
        os.makedirs(destino, exist_ok=True)
        img = Image.open(os.path.join(FONDOS, fondo)).convert("RGB").resize((1920, 1200))
        d = ImageDraw.Draw(img)
        x0, y0, x1, y1 = 420, 220, 1500, 900
        d.rectangle([x0 + 12, y0 + 16, x1 + 12, y1 + 16], fill=(0, 0, 0))
        img = img.filter(ImageFilter.GaussianBlur(0))
        d = ImageDraw.Draw(img)
        d.rectangle([x0, y0, x1, y0 + 56], fill=TITULO_ACTIVO)
        d.rectangle([x0, y0 + 56, x1, y1], fill=contenido)
        for i, cx in enumerate((x1 - 40, x1 - 100, x1 - 160)):
            d.ellipse([cx - 9, y0 + 19, cx + 9, y0 + 37],
                      outline=(232, 240, 250), width=3)
        d.rectangle([x0, y0 + 56, x0 + 280, y1], fill=tuple(max(0, c - 10) for c in contenido))
        d.rectangle([x0 + 20, y0 + 90, x0 + 260, y0 + 130], fill=(26, 127, 208))
        for i in range(6):
            d.rectangle([x0 + 320, y0 + 100 + i * 70, x1 - 60 - (i % 3) * 140, y0 + 120 + i * 70],
                        fill=tuple(int(t * 0.35 + c * 0.65) for t, c in zip(texto, contenido)))
        d.rectangle([0, 1200 - 64, 1920, 1200], fill=(10, 31, 54))
        img.save(os.path.join(destino, "fullscreenpreview.jpg"), quality=85)
        img.resize((640, 400), Image.LANCZOS).save(os.path.join(destino, "preview.png"))


def main():
    os.makedirs(FONDOS, exist_ok=True)
    for nombre, hacer in (("lazaro-pulso", fondo_pulso),
                          ("lazaro-amanecer", fondo_amanecer),
                          ("lazaro-claro", fondo_claro)):
        ruta = os.path.join(FONDOS, nombre + ".jpg")
        hacer().save(ruta, quality=90, optimize=True, progressive=True)
        print(ruta)
    apps = os.path.join(ICONOS, "scalable", "apps")
    os.makedirs(apps, exist_ok=True)
    with open(os.path.join(apps, "lazaro-menu.svg"), "w", encoding="utf-8") as f:
        f.write(icono_svg())
    for lado in (16, 22, 24):
        chico = os.path.join(ICONOS, f"{lado}x{lado}", "apps")
        os.makedirs(chico, exist_ok=True)
        with open(os.path.join(chico, "lazaro-menu.svg"), "w", encoding="utf-8") as f:
            f.write(icono_chico_svg(lado))
    simb = os.path.join(ICONOS, "symbolic", "apps")
    os.makedirs(simb, exist_ok=True)
    with open(os.path.join(simb, "lazaro-menu-symbolic.svg"), "w", encoding="utf-8") as f:
        f.write(icono_simbolico_svg())
    print(apps)
    tema_xfwm4()
    vistas_plasma()
    print(XFWM4)


if __name__ == "__main__":
    main()
