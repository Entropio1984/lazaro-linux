#!/bin/sh
# Prueba live/usr/sbin/lazaro-bienvenida sin abrir la ventana: que los
# archivos de funciones (un botón cada uno) estén bien escritos, que cada
# botón se muestre solo donde corresponde (sesión live o sistema
# instalado, y solo si está el programa que abre) y que un archivo mal
# escrito se detecte.
#
#   pruebas/bienvenida.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-bienvenida"
DATOS="$DIR/live/usr/share/lazaro/bienvenida"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }
es() { if eval "$2"; then ok "$1"; else mal "$1"; fi; }

# Programas de mentira: los que piden las funciones con Requiere.
mkdir -p "$TMP/bin" "$TMP/vacio"
for p in python3 sh; do ln -s "$(command -v "$p")" "$TMP/vacio/$p"; done
falsos="lazaro-abrir-instalador lazaro-manual alpine-update-launcher.sh lazaro-controladores
	lazaro-afinador lazaro-kernel lazaro-diagnostico lazaro-flatpak zenity xdg-open
	gtk-pipe-viewer mpv resolucion-modo-seguro"
for p in $falsos; do printf '#!/bin/sh\n' > "$TMP/bin/$p"; chmod +x "$TMP/bin/$p"; done

correr() { # DONDE PATH ORDEN
	LAZARO_BIENVENIDA_DIR="$DATOS" LAZARO_BIENVENIDA_DONDE="$1" PATH="$2" python3 "$PROG" "$3"
}

# 1. Los archivos de Lázaro están bien escritos.
es "los archivos de funciones están bien escritos" 'correr instalado "$TMP/vacio" --comprobar > "$TMP/c.txt" 2>&1'
cat "$TMP/c.txt"

# 2. Sistema instalado, con todo: se ven las del sistema, no el instalador.
correr instalado "$TMP/bin:$TMP/vacio" --listar > "$TMP/inst.txt"
es "instalado: se ve el Afinador" 'grep -q "	Afinador	visible	" "$TMP/inst.txt"'
es "instalado: se ve el Manual" 'grep -q "	Manual de Lázaro	visible	" "$TMP/inst.txt"'
es "instalado: se ve Flatpak y Flathub" 'grep -q "	Flatpak y Flathub	visible	" "$TMP/inst.txt"'
es "instalado: se ve el Diagnóstico" 'grep -q "	Diagnóstico	visible	" "$TMP/inst.txt"'
es "instalado: no se ve Instalar Lázaro" 'grep -q "	Instalar Lázaro	oculta	" "$TMP/inst.txt"'
# Sin tienda instalada (ni GNOME Software ni Discover), su botón no sale.
es "instalado sin tienda: no se ve la Tienda" 'grep -q "	Tienda de aplicaciones	oculta	" "$TMP/inst.txt"'
printf '#!/bin/sh\n' > "$TMP/bin/plasma-discover"; chmod +x "$TMP/bin/plasma-discover"
correr instalado "$TMP/bin:$TMP/vacio" --listar > "$TMP/inst2.txt"
es "instalado con Discover: se ve la Tienda" 'grep -q "	Tienda de aplicaciones	visible	" "$TMP/inst2.txt"'

# 3. Sesión live: el instalador sí; lo que cambia el sistema, no.
correr live "$TMP/bin:$TMP/vacio" --listar > "$TMP/live.txt"
es "live: se ve Instalar Lázaro" 'grep -q "	Instalar Lázaro	visible	" "$TMP/live.txt"'
es "live: se ve Controladores" 'grep -q "	Controladores	visible	" "$TMP/live.txt"'
es "live: no se ve el Kernel Lázaro" 'grep -q "	Kernel Lázaro	oculta	" "$TMP/live.txt"'
es "live: no se ve Actualizar el sistema" 'grep -q "	Actualizar el sistema	oculta	" "$TMP/live.txt"'

# 4. Sin los programas, los botones no salen (nada de botones rotos).
correr instalado "$TMP/vacio" --listar > "$TMP/nada.txt"
es "sin programas: ningún botón visible" '! grep -q "	visible	" "$TMP/nada.txt"'

# 5. Todas las funciones tienen su orden en el repositorio: lo que abren
#    existe en live/ o lo instala desktop-postinstall.sh (lista conocida).
externos="alpine-update-launcher.sh resolucion-modo-seguro gtk-pipe-viewer xdg-open lazaro-manual"
cut -f4 "$TMP/inst.txt" | while read -r prog _; do
	[ -e "$DIR/live/usr/sbin/$prog" ] || [ -e "$DIR/live/usr/bin/$prog" ] && continue
	case " $externos " in *" $prog "*) continue ;; esac
	echo "$prog"
done > "$TMP/huerfanos.txt"
es "cada botón abre un programa conocido" '[ ! -s "$TMP/huerfanos.txt" ]'
cat "$TMP/huerfanos.txt" >&2

# 6. Agregar una función es agregar un archivo; uno mal escrito se avisa
#    y no tumba a los demás.
mkdir -p "$TMP/extra/funciones"
cat > "$TMP/extra/funciones/90-nueva.conf" <<'EOS'
[Funcion]
Nombre=Función nueva
Descripcion=Una función agregada con un archivo.
Seccion=Sección nueva
Ejecutar=sh -c true
EOS
LAZARO_BIENVENIDA_DIR="$DATOS:$TMP/extra" LAZARO_BIENVENIDA_DONDE=instalado PATH="$TMP/vacio" python3 "$PROG" --listar > "$TMP/extra.txt"
es "un archivo nuevo agrega un botón y su sección" 'grep -q "^Sección nueva	Función nueva	visible	" "$TMP/extra.txt"'
printf '[Funcion]\nNombre=Sin orden\nSeccion=X\nDescripcion=Le falta Ejecutar.\nColor=rojo\n' > "$TMP/extra/funciones/91-mala.conf"
rc=0
LAZARO_BIENVENIDA_DIR="$DATOS:$TMP/extra" PATH="$TMP/vacio" python3 "$PROG" --comprobar > "$TMP/mala.txt" 2>&1 || rc=$?
es "un archivo mal escrito hace fallar --comprobar" '[ "$rc" != 0 ] && grep -q "91-mala.conf: falta Ejecutar" "$TMP/mala.txt" && grep -q "clave desconocida: color" "$TMP/mala.txt"'
LAZARO_BIENVENIDA_DIR="$DATOS:$TMP/extra" LAZARO_BIENVENIDA_DONDE=instalado PATH="$TMP/vacio" python3 "$PROG" --listar > "$TMP/extra2.txt" 2>/dev/null
es "el archivo malo no tumba a los demás" 'grep -q "Función nueva" "$TMP/extra2.txt" && ! grep -q "Sin orden" "$TMP/extra2.txt"'

# 7. Reemplazar una función de Lázaro: mismo nombre de archivo en otra carpeta.
printf '[Funcion]\nNombre=Diagnóstico propio\nDescripcion=Reemplazo.\nSeccion=Ayuda\nEjecutar=sh -c true\n' > "$TMP/extra/funciones/40-diagnostico.conf"
rm "$TMP/extra/funciones/91-mala.conf"
LAZARO_BIENVENIDA_DIR="$DATOS:$TMP/extra" LAZARO_BIENVENIDA_DONDE=instalado PATH="$TMP/vacio" python3 "$PROG" --listar > "$TMP/rep.txt"
es "un archivo con el mismo nombre reemplaza al de Lázaro" 'grep -q "Diagnóstico propio" "$TMP/rep.txt" && ! grep -q "	Diagnóstico	" "$TMP/rep.txt"'

# 8. La casilla "no mostrar al iniciar sesión" se respeta sin abrir ventana.
mkdir -p "$TMP/cfg/lazaro"; : > "$TMP/cfg/lazaro/bienvenida-no-mostrar"
rc=0
XDG_CONFIG_HOME="$TMP/cfg" LAZARO_BIENVENIDA_DONDE=instalado DISPLAY='' WAYLAND_DISPLAY='' python3 "$PROG" --sesion || rc=$?
es "--sesion no abre si la persona desmarcó la casilla" '[ "$rc" = 0 ]'

# 9. Los archivos del menú y del arranque con la sesión.
es "entrada del menú" 'grep -qx "Exec=lazaro-bienvenida" "$DIR/live/usr/share/applications/lazaro-bienvenida.desktop"'
es "arranque con la sesión" 'grep -qx "Exec=lazaro-bienvenida --sesion" "$DIR/live/usr/share/lazaro/lazaro-bienvenida-sesion.desktop"'
es "sintaxis de lazaro-flatpak" 'sh -n "$DIR/live/usr/sbin/lazaro-flatpak"'

echo
if [ "$fallos" -gt 0 ]; then
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
echo "Las $n pruebas pasaron."
