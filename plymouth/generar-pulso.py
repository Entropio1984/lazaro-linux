#!/usr/bin/env python3
"""Dibuja los cuadros de la animación de pulso del arranque (Plymouth).

Una línea de electrocardiograma azul neón recorre el ancho de izquierda a
derecha: la punta brilla y la línea se va apagando detrás. Los PNG se
guardan en el tema y se publican con el repositorio, así que compilar la
ISO no necesita Python ni Pillow; este script solo se corre para cambiar
el dibujo:

    python3 plymouth/generar-pulso.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ANCHO, ALTO = 640, 160
CUADROS = 60
COLOR = (46, 168, 255)          # azul neón
ESTELA = 0.75                   # parte del ancho que queda encendida detrás
DESTINO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "live", "usr", "share", "plymouth", "themes", "lazaro")


def altura(x):
    """Altura del latido en x (0..1): línea plana con un complejo PQRST
    cerca del centro. Devuelve un valor entre -1 (abajo) y 1 (arriba)."""
    def campana(centro, ancho, alto):
        return alto * math.exp(-((x - centro) / ancho) ** 2)
    return (campana(0.38, 0.025, 0.12)       # P
            + campana(0.47, 0.008, -0.18)    # Q
            + campana(0.50, 0.010, 1.00)     # R
            + campana(0.53, 0.010, -0.35)    # S
            + campana(0.64, 0.040, 0.22))    # T


def punto(i, pasos):
    x = i / pasos
    y = ALTO / 2 - altura(x) * (ALTO / 2 - 12)
    return x * (ANCHO - 1), y


def cuadro(n):
    pasos = 600
    cabeza = n / (CUADROS - 1)
    linea = Image.new("RGBA", (ANCHO, ALTO), (0, 0, 0, 0))
    dibujo = ImageDraw.Draw(linea)
    for i in range(pasos):
        x = i / pasos
        atraso = cabeza - x
        if atraso < 0 or atraso > ESTELA:
            continue
        brillo = 1 - atraso / ESTELA
        dibujo.line([punto(i, pasos), punto(i + 1, pasos)],
                    fill=COLOR + (int(255 * brillo ** 1.6),), width=4)
    # Resplandor: la misma línea, borrosa y más ancha, debajo.
    ancho = linea.filter(ImageFilter.GaussianBlur(10))
    cerca = linea.filter(ImageFilter.GaussianBlur(3))
    imagen = Image.alpha_composite(ancho, ancho)
    imagen = Image.alpha_composite(imagen, cerca)
    imagen = Image.alpha_composite(imagen, cerca)
    imagen = Image.alpha_composite(imagen, linea)
    # Punta blanca y brillante.
    if cabeza <= 1:
        px, py = punto(int(cabeza * pasos), pasos)
        punta = Image.new("RGBA", (ANCHO, ALTO), (0, 0, 0, 0))
        ImageDraw.Draw(punta).ellipse([px - 4, py - 4, px + 4, py + 4],
                                      fill=(220, 240, 255, 255))
        imagen = Image.alpha_composite(
            imagen, punta.filter(ImageFilter.GaussianBlur(2)))
    return imagen


def main():
    os.makedirs(DESTINO, exist_ok=True)
    for n in range(CUADROS):
        cuadro(n).save(os.path.join(DESTINO, f"pulso-{n}.png"), optimize=True)


if __name__ == "__main__":
    main()
