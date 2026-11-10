# Traducciones de las herramientas de Lázaro

Las herramientas de Lázaro (Bienvenida, Idioma y teclado, Actualizar,
Afinador, Controladores, Kernel Lázaro, Diagnóstico, Flatpak, el aviso de
la tarjeta gráfica y el instalador en modo texto) muestran sus textos en
el idioma de la sesión. Hoy hay **inglés** y **portugués de Brasil**.
Otra variante de un idioma traducido usa esa traducción (portugués de
Portugal → portugués de Brasil, más cercano que el inglés); cualquier
otro idioma sale en inglés, y en español salen tal cual están escritos
en los programas.

## Dónde está cada cosa

| Archivo | Qué es |
|---|---|
| `live/usr/share/lazaro/idiomas/en.po`, `pt_BR.po` | Las traducciones, una por idioma |
| `traducciones/lazaro.pot` | La plantilla: todos los textos para traducir, sin traducción |
| `traducciones/extraer.py` | Arma la plantilla y revisa las traducciones |
| `live/usr/share/lazaro/texto.sh` | Busca las traducciones para los programas de shell |
| `live/usr/share/lazaro/lazaro_texto.py` | Lo mismo para los de Python (Bienvenida, Idioma, Actualizar) |

Los `.po` son el formato de siempre para traducir programas libres. Cada
texto tiene dos líneas: `msgid` (el original en español, no se toca) y
`msgstr` (la traducción). Se pueden editar con
[Poedit](https://poedit.net/) o con cualquier editor de texto.

```
msgid "Cerrar"
msgstr "Close"
```

Reglas:

- `%s` es un dato que el programa pone después (una versión, un nombre
  de archivo...). La traducción debe tener **los mismos `%s`, en el
  mismo orden**.
- `\n` es un salto de línea. Los textos largos se parten en varias
  líneas entre comillas; es todo un mismo texto.
- Los nombres propios (Lázaro Linux, Alpine, Flathub, GParted) no se
  traducen.

## Corregir una traducción

Cambia el `msgstr` en el `.po` y comprueba:

```sh
python3 traducciones/extraer.py --revisar
sh pruebas/traducciones.sh
```

## Agregar o cambiar un texto en un programa

Los textos se marcan en el programa para que se traduzcan:

- shell: `zenity --text="$(_ 'Listo.')"`, y con datos
  `printf "$(_ 'Versión %s')" "$v"`;
- Python: `_("Listo.")`, y con datos `_("Versión %s") % v`;
- los botones de la Bienvenida (`bienvenida/funciones/*.conf`) y su
  portada (`bienvenida/portada.txt`) se traducen solos: no hay que
  marcar nada.

Después:

```sh
python3 traducciones/extraer.py --actualizar
```

Eso rehace `lazaro.pot` y agrega los textos nuevos, vacíos, al final de
cada `.po`. Tradúcelos ahí. La prueba automática falla mientras falte
alguno, así ningún cambio llega a la ISO a medio traducir.

## Agregar un idioma

1. Copia la plantilla con el código del idioma:
   `cp traducciones/lazaro.pot live/usr/share/lazaro/idiomas/fr.po`
   (francés: `fr`; con país: `pt_BR`, `es_AR`...).
2. Cambia la línea `"Language: ..."` del principio y traduce cada
   `msgstr`.
3. Agrega `Name[fr]=` (y `Comment[fr]=` donde haya `Comment`) a los
   menús: `live/usr/share/applications/lazaro-*.desktop`,
   `live/etc/xdg/autostart/lazaro-*.desktop` y
   `live/usr/share/lazaro/lazaro-*.desktop`.
4. Corre `sh pruebas/traducciones.sh`.

Para que la sesión de prueba ofrezca ese idioma, además hay que sumarlo
a la lista de `lazaro-idioma` (y a Calamares, que ya trae muchos).

## Qué no se traduce todavía

- El informe del Diagnóstico queda en español a propósito, para que
  quien ayuda lo lea siempre igual.
- Los mensajes para la terminal de uso técnico (los de error de las
  opciones `--algo`).
- El Manual de Lázaro (PDF) está solo en español.
- Los textos propios de Lázaro dentro del instalador gráfico
  (Calamares): la elección de escritorio está en español e inglés; la
  lista de programas adicionales y la presentación mientras instala,
  solo en español. Lo demás de Calamares viene traducido por su
  proyecto.
