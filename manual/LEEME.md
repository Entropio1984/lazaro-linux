# Manual de Lázaro Linux (fuentes en LaTeX)

Esta carpeta tiene el código del **Manual de Lázaro Linux**, el PDF que
viene dentro de la ISO (icono "Manual de Lázaro" en el escritorio de la
sesión de prueba y en el menú del sistema instalado) y que también se
descarga suelto junto a cada ISO.

GitHub compila el PDF solo en cada cambio (trabajo "Manual (PDF)" del
flujo de la ISO). No hace falta instalar nada para editarlo: basta con
cambiar los archivos `.tex` y abrir un PR; el PDF de prueba queda en los
"Artifacts" de la compilación, con el nombre `manual`.

## Qué hay en cada archivo

| Archivo | Para qué |
|---|---|
| `lazaro-manual.tex` | El libro: el orden de las partes y los capítulos |
| `preambulo.tex` | La apariencia: letras, colores, recuadros |
| `portada.tex` | La portada y la página de la licencia |
| `capitulos/` | Un archivo por capítulo (`01-bienvenida.tex`, ...) |
| `referencias.bib` | Las fuentes citadas (bibliografía) |
| `imagenes/` | Logo e imágenes; `imagenes/capturas/` las capturas de pantalla |
| `compilar.sh` | Compila el PDF en tu equipo |

Las imágenes de los escritorios se toman directamente de la ISO
(`live/usr/share/calamares/branding/lazaro/`), así hay una sola copia.

## Cómo se escribe

- Capítulo, sección y subsección: `\chapter{...}`, `\section{...}`,
  `\subsection{...}`.
- Negrita y cursiva: `\textbf{...}` y `\emph{...}`.
- Recuadros: `\begin{consejo} ... \end{consejo}`, lo mismo con `cuidado`
  y `nota`.
- Pasos numerados grandes: `\begin{pasos} \item ... \item ... \end{pasos}`.
- Menús y teclas: `\menu{Archivo > Guardar}` y `\keys{\ctrl + C}`.
- Lo que se escribe en la terminal: `\begin{terminal} ... \end{terminal}`.
- Una captura: `\captura{nombre}{Texto debajo de la imagen}` busca
  `imagenes/capturas/nombre.png` (o `.jpg`). Mientras no exista, el PDF
  muestra un recuadro gris "Captura pendiente" en su lugar.
- Citar una fuente: `\cite{clave}`, con la clave de `referencias.bib`. Al
  final de cada capítulo, `\fuentes` imprime las fuentes de ese capítulo.
- Referirse a otro capítulo: `capítulo~\ref{cap:16-problemas}`.

## Compilar en tu equipo (opcional)

En CachyOS o Arch:

```sh
sudo pacman -S texlive-basic texlive-latex texlive-latexrecommended \
  texlive-latexextra texlive-fontsrecommended texlive-langspanish \
  texlive-bibtexextra biber ghostscript
./manual/compilar.sh
```

En Debian, Ubuntu o MX Linux:

```sh
sudo apt install latexmk texlive-latex-extra texlive-lang-spanish \
  texlive-fonts-recommended tex-gyre lmodern texlive-bibtex-extra biber ghostscript
./manual/compilar.sh
```

El resultado queda en `manual/lazaro-manual.pdf`. También se puede editar
en un editor de LaTeX con vista previa, como TeXstudio o Overleaf
(subiendo la carpeta `manual/` completa; compilador pdfLaTeX, bibliografía
con Biber).

## Capturas de pantalla

- Formato PNG, de la ventana o la pantalla a 1280×800 o menos.
- Con el escritorio XFCE (el de fábrica) y en español, salvo en las
  secciones de otros escritorios.
- Sin datos personales (nombres de red wifi, correos, archivos propios).

Casi todas se sacan solas en una máquina virtual: en GitHub, pestaña
**Actions** → **Capturas del manual** → **Run workflow**. Tarda alrededor
de una hora y deja las imágenes en `imagenes/capturas/` (en `main`, como
un PR). El recorrido está en
`live/usr/share/lazaro/pruebas/zz-lazaro-capturas.start`.

Estas hay que sacarlas a mano en un equipo real, porque la máquina
virtual no las puede mostrar bien: `wifi-lista` (redes wifi),
`tienda` (la tienda necesita su catálogo de internet) y `actualizar`
(pide la contraseña). En XFCE: tecla **Impr Pant**, que abre la
herramienta de capturas.

## Licencia

Texto e imágenes: CC BY-SA 4.0 (ver `LICENCIA.md`).
