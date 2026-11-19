#!/bin/sh
# Instala paquetes de Ubuntu en las compilaciones de GitHub sin quedarse
# colgado cuando el servidor de Ubuntu está lento (2026-11-18 bajaba a
# pocos KB/s y la instalación de LaTeX llegaba al límite de tiempo).
#
#   .github/instalar-paquetes.sh paquete...
#
# - Usa los .deb guardados en ~/latex-debs (caché entre compilaciones).
# - Si un servidor tarda más de 7 minutos, prueba con otro.
# - Al terminar copia los .deb a ~/latex-debs y, si hay alguno nuevo,
#   escribe nuevo=1 en $GITHUB_OUTPUT para guardar la caché.
set -u
guardados=$HOME/latex-debs
mkdir -p "$guardados"
antes=$(ls "$guardados" | wc -l)
sudo cp "$guardados"/*.deb /var/cache/apt/archives/ 2>/dev/null || true

fuente=/etc/apt/sources.list.d/ubuntu.sources
original=$(sed -n 's|^URIs: *\(http[^ ]*/ubuntu/\?\).*|\1|p' "$fuente" | head -n1)
listo=0
for espejo in "$original" http://archive.ubuntu.com/ubuntu/ \
    http://mirrors.edge.kernel.org/ubuntu/ http://mirror.math.princeton.edu/pub/ubuntu/; do
  [ -n "$espejo" ] || continue
  echo "== Probando $espejo"
  sudo dpkg --configure -a || true
  sudo sed -i "s|^URIs: *http[^ ]*/ubuntu/\?\$|URIs: $espejo|" "$fuente"
  rc=0
  sudo timeout 120 apt-get update -q || rc=$?
  if [ "$rc" -eq 0 ]; then
    sudo timeout 420 apt-get install -y -q --no-install-recommends "$@" || rc=$?
    if [ "$rc" -eq 0 ]; then listo=1; break; fi
  fi
  echo "::warning::El servidor $espejo no sirvió (código $rc); pruebo otro."
done

cp -n /var/cache/apt/archives/*.deb "$guardados"/ 2>/dev/null || true
despues=$(ls "$guardados" | wc -l)
if [ "$despues" -gt "$antes" ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "nuevo=1" >> "$GITHUB_OUTPUT"
fi
[ "$listo" = 1 ] || { echo "::error::No se pudieron instalar los paquetes desde ningún servidor."; exit 1; }
