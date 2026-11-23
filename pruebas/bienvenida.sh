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

# Que el resultado no dependa de lo que tenga instalado esta máquina
# (por ejemplo xdg-open en /usr/bin): buscar programas solo en el PATH.
export LAZARO_BIENVENIDA_SOLO_PATH=1

# Programas de mentira: los que piden las funciones con Requiere.
mkdir -p "$TMP/bin" "$TMP/vacio"
for p in python3 sh; do ln -s "$(command -v "$p")" "$TMP/vacio/$p"; done
falsos="lazaro-abrir-instalador lazaro-manual alpine-update-root.sh lazaro-actualizador lazaro-controladores
	lazaro-afinador lazaro-kernel lazaro-diagnostico lazaro-flatpak lazaro-nubes zenity xdg-open
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
es "instalado: se ve Aplicaciones de Flathub" 'grep -q "	Aplicaciones de Flathub	visible	" "$TMP/inst.txt"'
es "instalado: se ve Nubes" 'grep -q "	Lázaro Nubes: Google Drive, OneDrive y Dropbox	visible	" "$TMP/inst.txt"'
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
externos="resolucion-modo-seguro gtk-pipe-viewer xdg-open lazaro-manual"
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

# El informe del Diagnóstico no lleva lo privado: contraseñas de
# direcciones y de carpetas de red, la mitad de cada MAC ni las IPv6
# públicas (función censurar).
awk '/^censurar\(\) \{/,/^\}/' "$DIR/live/usr/sbin/lazaro-diagnostico" > "$TMP/censurar.sh"
censura() { sh -c '. "$1"; printf "%s\n" "$2" | censurar' _ "$TMP/censurar.sh" "$1"; }
es "el Diagnóstico tapa las contraseñas de las direcciones" '[ "$(censura "https://ana:secreto@sitio.org/alpine/v3.24/main")" = "https://***@sitio.org/alpine/v3.24/main" ]'
es "el Diagnóstico tapa las contraseñas de carpetas de red" '[ "$(censura "//srv/doc /mnt cifs username=ana,password=s3cr3t,uid=1000 0 0")" = "//srv/doc /mnt cifs username=ana,password=***,uid=1000 0 0" ]'
es "el Diagnóstico tapa una contraseña con comas dobles" '[ "$(censura "//srv/doc /mnt cifs password=a,,b,uid=1000 0 0")" = "//srv/doc /mnt cifs password=***,uid=1000 0 0" ]'
es "el Diagnóstico tapa la mitad de la MAC" '[ "$(censura "link/ether 00:1b:2c:3d:4e:5f brd ff:ff:ff:ff:ff:ff")" = "link/ether 00:1b:2c:xx:xx:xx brd ff:ff:ff:xx:xx:xx" ]'
es "el Diagnóstico tapa la IPv6 pública y deja la local" '[ "$(censura "inet6 2800:e2:1c00::5/64 scope global dynamic")" = "inet6 ***/64 scope global dynamic" ] && [ "$(censura "inet6 fe80::1/64 scope link")" = "inet6 fe80::1/64 scope link" ]'

# El Actualizador (lazaro-actualizador), sin abrir la ventana: cuándo
# ofrece pasar a la versión siguiente de Alpine y cómo limpia el avance.
cat > "$TMP/act.py" <<'EOS'
import importlib.machinery, importlib.util, os, sys, tempfile
cargador = importlib.machinery.SourceFileLoader("act", sys.argv[1])
act = importlib.util.module_from_spec(importlib.util.spec_from_loader("act", cargador))
cargador.exec_module(act)
os.environ.pop("LAZARO_ACTUALIZADOR_SIGUIENTE", None)
d = tempfile.mkdtemp()
def repos(texto):
    r = os.path.join(d, "repositories")
    open(r, "w").write(texto)
    return r
def espejo(ultima, tiene_siguiente=True):
    def bajar(url, solo_ver=False):
        if solo_ver:
            if not tiene_siguiente:
                raise OSError("404")
            return ""
        return "---\n-\n  branch: v3.%d\n  arch: x86_64\n" % ultima
    return bajar
def sin_red(url, solo_ver=False):
    raise OSError("sin internet")
fijo = repos("https://dl-cdn.alpinelinux.org/alpine/v3.24/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.24/community\n")
casos = [
    ("hay versión nueva", act.siguiente_version(fijo, espejo(25)), ("3.24", "3.25")),
    ("dos versiones adelante: solo la siguiente", act.siguiente_version(fijo, espejo(26)), ("3.24", "3.25")),
    ("ya es la última", act.siguiente_version(fijo, espejo(24)), None),
    ("el espejo aún no tiene la siguiente", act.siguiente_version(fijo, espejo(25, False)), None),
    ("sin internet", act.siguiente_version(fijo, sin_red), None),
    ("edge no se toca", act.siguiente_version(repos("https://dl-cdn.alpinelinux.org/alpine/edge/main\n"), espejo(25)), None),
    ("sin archivo de repositorios", act.siguiente_version(os.path.join(d, "no-existe"), espejo(25)), None),
    ("limpia el prefijo", act.limpiar("# (1/3) Upgrading musl\r"), "(1/3) Upgrading musl"),
    ("limpia los colores", act.limpiar("\x1b[32mOK\x1b[0m: 12 MiB"), "OK: 12 MiB"),
    ("orden normal", act.orden_de_actualizar(""), ["pkexec", "/usr/local/bin/alpine-update-root.sh"]),
    ("orden con versión nueva", act.orden_de_actualizar("--nueva-version"),
     ["pkexec", "/usr/local/bin/alpine-update-root.sh", "--nueva-version"]),
]
mal = [n for n, sale, espera in casos if sale != espera]
for n, sale, espera in casos:
    print("%s  %s" % ("ok  " if sale == espera else "FALLO", n))
sys.exit(1 if mal else 0)
EOS
es "actualizador: versión siguiente, limpieza y orden" 'env -u LAZARO_ACTUALIZADOR_ORDEN python3 "$TMP/act.py" "$DIR/live/usr/sbin/lazaro-actualizador" > "$TMP/act.txt" 2>&1'
cat "$TMP/act.txt"
rc=0
python3 "$DIR/live/usr/sbin/lazaro-actualizador" --otra > /dev/null 2> "$TMP/otra.txt" || rc=$?
es "actualizador: una orden desconocida se rechaza" '[ "$rc" = 2 ] && grep -q "^Uso: lazaro-actualizador" "$TMP/otra.txt"'

# 9. Los archivos del menú y del arranque con la sesión.
es "entrada del menú" 'grep -qx "Exec=lazaro-bienvenida" "$DIR/live/usr/share/applications/lazaro-bienvenida.desktop"'
es "arranque con la sesión" 'grep -qx "Exec=lazaro-bienvenida --sesion" "$DIR/live/usr/share/lazaro/lazaro-bienvenida-sesion.desktop"'
es "sintaxis de lazaro-flatpak" 'sh -n "$DIR/live/usr/sbin/lazaro-flatpak"'

# 10. lazaro-flatpak (botón "Aplicaciones de Flathub"), con un flatpak de
# mentira: activa Flathub, instala lo elegido y avisa lo que falló.
FP="$TMP/fp"
mkdir -p "$FP/bin"
cat > "$FP/bin/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
	remotes) [ ! -e "$FP_DIR/remoto" ] || echo flathub ;;
	remote-add) [ "$*" = "remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ] || exit 1
		touch "$FP_DIR/remoto" ;;
	list) cat "$FP_DIR/apps" 2>/dev/null ;;
	install) [ "$1 $2 $3 $4 $5" = "install --system -y --noninteractive flathub" ] || exit 1
		[ "$6" != "${FP_FALLA:-}" ] || exit 1; echo "$6" >> "$FP_DIR/apps" ;;
	info) grep -qx "$3" "$FP_DIR/apps" 2>/dev/null ;;
esac
EOF
chmod +x "$FP/bin/flatpak"
fp() { FP_DIR="$FP" PATH="$FP/bin:$PATH" LAZARO_FLATPAK_SIN_APK=1 LAZARO_FLATPAK_ESPERA=0 sh "$DIR/live/usr/sbin/lazaro-flatpak" "$@"; }
es "flatpak: sin activar dice falta" '[ "$(fp --estado)" = falta ]'
es "flatpak: activa e instala OnlyOffice y Brave" 'fp --activar onlyoffice com.brave.Browser > "$TMP/fp1.txt" 2>&1 && [ "$(fp --estado)" = activo ] && [ "$(fp --instaladas | tr "\n" " ")" = "org.onlyoffice.desktopeditors com.brave.Browser " ]'
es "flatpak: avanza por pasos para la barra" 'grep -qx "# Descargando Brave (paso 3 de 3). Puede tardar varios minutos…" "$TMP/fp1.txt"'
echo org.otra.Aplicacion >> "$FP/apps"
es "flatpak: --instaladas solo nombra las de la lista" '! fp --instaladas | grep -q otra'
rc=0; FP_FALLA=com.google.Chrome fp --activar chrome > "$TMP/fp2.txt" 2>&1 || rc=$?
es "flatpak: si una aplicación falla termina con 3" '[ "$rc" = 3 ] && grep -q "No se pudo instalar: Google Chrome" "$TMP/fp2.txt"'

# Tienda: un Discover escondido (sigue vivo tras cerrar su ventana) se
# cierra antes de abrir uno nuevo; si apk trabaja, se deja.
TD="$TMP/tienda"
mkdir -p "$TD/bin"
cat > "$TD/bin/plasma-discover" <<'EOF2'
#!/bin/sh
echo abierta >> "$TD_DIR/log"
EOF2
cat > "$TD/bin/pgrep" <<'EOF2'
#!/bin/sh
case "$*" in
	*plasma-discover*) p="$(cat "$TD_DIR/vivo" 2>/dev/null)" && kill -0 "$p" 2>/dev/null && echo "$p" ;;
	*apk*) [ -e "$TD_DIR/apk" ] ;;
	*) exit 1 ;;
esac
EOF2
chmod +x "$TD/bin/"*
td() { : > "$TD/log"; TD_DIR="$TD" PATH="$TD/bin:$PATH" XDG_CURRENT_DESKTOP=LXQt sh "$DIR/live/usr/sbin/lazaro-flatpak" --tienda >/dev/null 2>&1; }
td
es "tienda: sin Discover corriendo solo lo abre" '[ "$(cat "$TD/log")" = abierta ]'
# El Discover escondido es un proceso de verdad (sleep).
sleep 60 & echo $! > "$TD/vivo"; td
es "tienda: un Discover escondido se cierra y se abre otro" '! kill -0 "$(cat "$TD/vivo")" 2>/dev/null && [ "$(cat "$TD/log")" = abierta ]'
sleep 60 & echo $! > "$TD/vivo"; touch "$TD/apk"; td
es "tienda: si apk trabaja no se cierra" 'kill -0 "$(cat "$TD/vivo")" 2>/dev/null && [ "$(cat "$TD/log")" = abierta ]'
kill "$(cat "$TD/vivo")" 2>/dev/null || true
rc=0; fp --activar zoom > /dev/null 2>&1 || rc=$?
es "flatpak: una aplicación desconocida se rechaza" '[ "$rc" = 2 ]'

# 11. lazaro-nubes (botón "Nubes"): sin paquetes de Alpine, instala la
# aplicación de verdad (su instalar.sh) en una carpeta personal de
# mentira, dice si está al día y la pone al día si Lázaro trae otra.
es "sintaxis de lazaro-nubes" 'sh -n "$DIR/live/usr/sbin/lazaro-nubes"'
es "sintaxis del instalador de Lázaro Nubes" 'sh -n "$DIR/live/usr/share/lazaro/nubes-rclone/instalar.sh"'
es "Lázaro Nubes: el programa compila" 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$DIR"/live/usr/share/lazaro/nubes-rclone/*.py'
# Colores del escritorio (nubes_tema.py): sin pantalla no cambia nada y
# las cuentas de colores dan lo esperado.
es "Lázaro Nubes: sin pantalla sigue con su aspecto de siempre" 'env -u DISPLAY -u WAYLAND_DISPLAY python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import nubes_tema as t; sys.exit(0 if t.leer_tema() is None and t.FAMILIA == \"TkDefaultFont\" else 1)" "$DIR/live/usr/share/lazaro/nubes-rclone"'
es "Lázaro Nubes: mezcla y brillo de colores" 'python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import nubes_tema as t; sys.exit(0 if t._mezcla(\"#000000\", \"#ffffff\", 0.5) == \"#808080\" and t._luz(\"#303030\") < 0.5 < t._luz(\"#f6f5f4\") else 1)" "$DIR/live/usr/share/lazaro/nubes-rclone"'
rc=0; sh "$DIR/live/usr/sbin/lazaro-nubes" --otra > /dev/null 2>&1 || rc=$?
es "nubes: una orden desconocida se rechaza" '[ "$rc" = 2 ]'
if [ "$(id -u)" != 0 ]; then
	NU="$TMP/nubes"
	mkdir -p "$NU/casa" "$NU/app"
	cp "$DIR"/live/usr/share/lazaro/nubes-rclone/* "$NU/app/"
	nu() { env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		HOME="$NU/casa" LAZARO_NUBES_DIR="$NU/app" LAZARO_NUBES_SIN_APK=1 XDG_CURRENT_DESKTOP=XFCE \
		sh "$DIR/live/usr/sbin/lazaro-nubes" "$@"; }
	es "nubes: antes de instalar falta la aplicación" '[ "$(nu --estado)" = falta-app ]'
	es "nubes: instala la aplicación en la carpeta personal" 'nu --app > "$TMP/nu1.txt" 2>&1 && [ "$(nu --estado)" = lista ]'
	es "nubes: deja el lanzador y la entrada del menú" '"$NU/casa/.local/bin/nubes-rclone" --version | grep -q "^Lázaro Nubes " && grep -q "^Exec=.*nubes-rclone" "$NU/casa/.local/share/applications/nubes-rclone.desktop"'
	es "nubes: deja el icono junto al reloj al iniciar sesión" 'grep -q "^Exec=.*nubes-rclone --bandeja" "$NU/casa/.config/autostart/nubes-rclone-bandeja.desktop"'
	echo "# cambio" >> "$NU/app/nubes_rclone.py"
	es "nubes: si Lázaro trae otra versión, no está al día" '[ "$(nu --estado)" = falta-app ]'
	es "nubes: se pone al día" 'nu --app > "$TMP/nu2.txt" 2>&1 && [ "$(nu --estado)" = lista ]'
else
	echo "(como administrador no se prueba instalar Lázaro Nubes: su instalador no corre como root)"
fi

echo
if [ "$fallos" -gt 0 ]; then
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
echo "Las $n pruebas pasaron."
