#!/bin/sh
# Compila el Manual de Lázaro Linux (manual/lazaro-manual.pdf).
#
#   ./manual/compilar.sh
#
# Necesita LaTeX con latexmk y biber. En CachyOS/Arch:
#   sudo pacman -S texlive-basic texlive-latex texlive-latexrecommended \
#     texlive-latexextra texlive-fontsrecommended texlive-langspanish \
#     texlive-bibtexextra biber
# En Debian/Ubuntu/MX:
#   sudo apt install latexmk texlive-latex-extra texlive-lang-spanish \
#     texlive-fonts-recommended texlive-bibtex-extra biber
#
# Después comprime las imágenes del PDF (si está instalado Ghostscript)
# para que no pese en la ISO.
set -eu
cd "$(dirname "$0")"

# La versión y la fecha del manual salen de config.env, igual que la ISO.
. ../config.env
FECHA="${LAZARO_MANUAL_FECHA:-$(date -u '+%Y-%m-%d')}"
printf '\\newcommand{\\lazaroversion}{%s}\n\\newcommand{\\lazarofecha}{%s}\n' \
	"$ISO_VERSION" "$FECHA" > version.tex

latexmk -pdf -interaction=nonstopmode -halt-on-error lazaro-manual.tex

# Avisos que conviene ver: referencias rotas o citas sin entrada.
if grep -E "undefined|Citation .* undefined" lazaro-manual.log | grep -v "^Package rerunfilecheck"; then
	echo "AVISO: hay referencias sin resolver (ver arriba)" >&2
fi

if command -v gs >/dev/null 2>&1; then
	gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.6 \
		-dPDFSETTINGS=/ebook -dDetectDuplicateImages=true \
		-sOutputFile=lazaro-manual.min.pdf lazaro-manual.pdf
	# Solo se queda con la versión comprimida si de verdad pesa menos.
	if [ "$(wc -c < lazaro-manual.min.pdf)" -lt "$(wc -c < lazaro-manual.pdf)" ]; then
		mv lazaro-manual.min.pdf lazaro-manual.pdf
	else
		rm -f lazaro-manual.min.pdf
	fi
fi
echo "Listo: manual/lazaro-manual.pdf ($(du -h lazaro-manual.pdf | cut -f1))"
