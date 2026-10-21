#!/usr/bin/env python3
# Lázaro Linux: lee lo que se marcó en la pantalla "Software adicional"
# (módulo netinstall) y lo deja como texto en globalstorage, en la clave
# "lazaroExtras", para que shellprocess@ajustes se lo pase a
# lazaro-instalar. netinstall guarda la elección en "packageOperations",
# una lista que shellprocess no puede leer. Aquí no se instala nada: los
# nombres son marcas propias (vlc, chrome...) que lazaro-instalar traduce.

import libcalamares


def pretty_name():
    return "Anotando el software adicional"


def nombres(operaciones):
    elegidos = []
    for operacion in operaciones or []:
        if not isinstance(operacion, dict):
            continue
        for clave in ("install", "try_install"):
            for paquete in operacion.get(clave) or []:
                if isinstance(paquete, dict):
                    paquete = paquete.get("package") or paquete.get("name") or ""
                paquete = str(paquete).strip()
                if paquete and paquete not in elegidos:
                    elegidos.append(paquete)
    return elegidos


def run():
    gs = libcalamares.globalstorage
    operaciones = gs.value("packageOperations") if gs.contains("packageOperations") else []
    # "base" va siempre delante: así lazaro-instalar distingue "no se
    # marcó nada" de "no lo llamó Calamares" (entonces usa lo de siempre).
    gs.insert("lazaroExtras", " ".join(["base"] + nombres(operaciones)))
    libcalamares.utils.debug("lazaroExtras: " + gs.value("lazaroExtras"))
    return None
