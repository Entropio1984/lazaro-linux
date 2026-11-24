#!/bin/sh
# Instalador de «Lázaro Nubes» para cualquier distribución Linux.
# Escrito en sh POSIX: funciona con bash, dash y el ash de BusyBox (Alpine).
#
#   ./instalar.sh                      instala dependencias y la aplicación
#   ./instalar.sh --sin-dependencias   solo instala la aplicación (sin sudo)
#   ./instalar.sh --equipo-compartido  además activa el modo para aulas (cuenta compartida)
#   ./instalar.sh --desinstalar        quita la aplicación (no toca tus nubes, carpetas ni rclone)
#
# Además del programa, instala el icono del área de notificaciones
# (sincronización, pausa, archivos nuevos) y lo configura para iniciarse solo.
# Ejecútalo con tu usuario normal (NO con sudo): pedirá permisos solo cuando los necesite.

set -eu

APP_ID="nubes-rclone"
VERSION_MINIMA_RCLONE="1.66"
ORIGEN="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
DESTINO="$DATA/$APP_ID"
BIN="$HOME/.local/bin"
LANZADOR="$DATA/applications/$APP_ID.desktop"
ICONO="$DATA/icons/hicolor/scalable/apps/$APP_ID.svg"
# Misma carpeta de ejecución que usa la aplicación (sockets, bloqueos, peticiones)
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ] \
   && [ "$(ls -ldn "$XDG_RUNTIME_DIR" | awk '{print $3}')" = "$(id -u)" ]; then
    EJEC="$XDG_RUNTIME_DIR/$APP_ID"
else
    EJEC="$CACHE/$APP_ID/ejecucion"
fi

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
aviso() { printf '\033[1;33m !\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m ✘\033[0m %s\n' "$*" >&2; }

# Instalar como root dejaría el programa en /root o archivos de root en tu carpeta personal
if [ "$(id -u)" -eq 0 ]; then
    error "No ejecutes el instalador como root (ni con sudo)."
    error "Ejecútalo con tu usuario normal: ./instalar.sh  — pedirá la contraseña cuando haga falta."
    exit 1
fi

# ---------------------------------------------------------------- privilegios
como_root() {
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        doas "$@"
    else
        # su -c recibe una sola cadena: citamos cada argumento
        cmd=""
        for a in "$@"; do cmd="$cmd '$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'"; done
        su -c "$cmd"
    fi
}

# Escapa una ruta para la línea Exec= de un archivo .desktop (especificación freedesktop)
exec_desktop() {
    case "$1" in
        *[!A-Za-z0-9_./=-]*) printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"`$]/\\&/g')" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Cambia un archivo sin «sed -i» (no es POSIX): se escribe en temporal y se mueve
reemplazar_exec() {   # $1=archivo  $2=nueva línea Exec completa
    tmp_desk="$1.tmp.$$"
    while IFS= read -r linea || [ -n "$linea" ]; do
        case "$linea" in Exec=*) printf '%s\n' "$2" ;; *) printf '%s\n' "$linea" ;; esac
    done < "$1" > "$tmp_desk"
    mv "$tmp_desk" "$1"
}

# Pide al icono de la bandeja que se cierre y espera a que suelte su bloqueo
cerrar_icono() {
    # Ubicación actual; la antigua (versiones anteriores) solo si existe
    if [ -f "$EJEC/bandeja.lock" ]; then
        mkdir -p -m 700 "$EJEC/peticiones" && : > "$EJEC/peticiones/salir"
    fi
    if [ -f "$CACHE/$APP_ID/bandeja.lock" ]; then
        mkdir -p -m 700 "$CACHE/$APP_ID/peticiones" && : > "$CACHE/$APP_ID/peticiones/salir"
    fi
    command -v python3 >/dev/null 2>&1 || { sleep 6; return 0; }
    i=0
    while [ $i -lt 30 ]; do
        if python3 - "$EJEC/bandeja.lock" "$CACHE/$APP_ID/bandeja.lock" <<'PYEOF'
import fcntl, os, sys
for ruta in sys.argv[1:]:
    if not os.path.exists(ruta):
        continue             # no se crean bloqueos vacíos donde no los había
    try:
        with open(ruta, "a") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(1)          # sigue en marcha
PYEOF
        then break; fi
        sleep 1; i=$((i + 1))
    done
    rm -f "$EJEC/peticiones/salir" "$CACHE/$APP_ID/peticiones/salir"
}

# -------------------------------------------------------------- desinstalar
desinstalar() {
    info "Desinstalando $APP_ID…"
    if [ -x "$BIN/$APP_ID" ]; then
        "$BIN/$APP_ID" --desmontar-todo || true
    fi
    cerrar_icono
    rm -rf "$DESTINO"
    rm -f "$BIN/$APP_ID" "$LANZADOR" "$ICONO" "$CONFIG/autostart/$APP_ID-automontaje.desktop" \
          "$CONFIG/autostart/$APP_ID-bandeja.desktop"
    rm -f "$(dirname "$ICONO")/$APP_ID"-*.svg
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" 2>/dev/null || true
    ok "Aplicación eliminada."
    aviso "Se conservan tus conexiones de rclone (~/.config/rclone/rclone.conf), los ajustes ($CONFIG/$APP_ID)"
    aviso "y tus carpetas sincronizadas con todos sus archivos."
    exit 0
}

# ------------------------------------------------------------- dependencias
# Cada grupo de paquetes se instala por separado: si la distribución no tiene rclone
# (p. ej. Alpine sin el repositorio «community»), el resto se instala igual y luego
# se ofrece el binario oficial.
instalar_dependencias() {
    info "Instalando dependencias (FUSE, Python con Tkinter, xdg-utils, rclone)…"
    BASE="" RCLONE="rclone" GOBJECT="" GTK="" XDG="xdg-utils"
    if command -v apk >/dev/null 2>&1; then
        INST="apk add"
        BASE="fuse3 python3 python3-tkinter"
        GOBJECT="py3-gobject3"; GTK="gtk+3.0"
        if ! grep -Eq '^[^#].*/community/?$' /etc/apk/repositories 2>/dev/null; then
            aviso "El repositorio «community» de Alpine no está activado: ahí están rclone y py3-gobject3."
            aviso "Actívalo quitando el «#» de la línea …/community en /etc/apk/repositories y ejecuta «doas apk update»."
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        como_root apt-get update || true
        INST="apt-get install -y"
        BASE="fuse3 python3 python3-tk"; GOBJECT="python3-gi"; GTK="gir1.2-gtk-3.0"
    elif command -v dnf >/dev/null 2>&1; then
        INST="dnf install -y"
        BASE="fuse3 python3 python3-tkinter"; GOBJECT="python3-gobject"; GTK="gtk3"
    elif command -v yum >/dev/null 2>&1; then
        como_root yum install -y epel-release || true
        INST="yum install -y"
        BASE="fuse3 python3 python3-tkinter"; GOBJECT="python3-gobject"; GTK="gtk3"
    elif command -v pacman >/dev/null 2>&1; then
        INST="pacman -S --needed --noconfirm"
        BASE="fuse3 python tk"; GOBJECT="python-gobject"; GTK="gtk3"
    elif command -v zypper >/dev/null 2>&1; then
        INST="zypper --non-interactive install"
        BASE="fuse3 python3 python3-tk"; GOBJECT="python3-gobject"; GTK="typelib-1_0-Gtk-3_0"
    elif command -v xbps-install >/dev/null 2>&1; then
        INST="xbps-install -Sy"
        BASE="fuse3 python3 python3-tkinter"; GOBJECT="python3-gobject"; GTK="gtk+3"
    elif command -v eopkg >/dev/null 2>&1; then
        INST="eopkg install -y"
        BASE="fuse3 python3 python3-tkinter"; GOBJECT="python3-gobject"; GTK=""
    elif command -v emerge >/dev/null 2>&1; then
        aviso "Gentoo: asegúrate de tener dev-lang/python con USE=tk."
        INST="emerge --noreplace"
        BASE="sys-fs/fuse:3"; XDG="x11-misc/xdg-utils"; RCLONE="net-misc/rclone"; GOBJECT="dev-python/pygobject"
    else
        aviso "No reconozco tu gestor de paquetes."
        aviso "Instala a mano: rclone, fuse3, python3 con tkinter, PyGObject y xdg-utils."
        return 0
    fi
    # shellcheck disable=SC2086
    como_root $INST $BASE || aviso "No se pudieron instalar algunos paquetes básicos: $BASE"
    # shellcheck disable=SC2086
    como_root $INST $XDG || aviso "No se pudo instalar xdg-utils (abrir carpetas y enlaces): se usarán alternativas."
    # shellcheck disable=SC2086
    como_root $INST $RCLONE || aviso "La distribución no ofrece rclone: se ofrecerá el binario oficial."
    if ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null && [ -n "$GOBJECT" ]; then
        info "Instalando PyGObject (icono del área de notificaciones)…"
        # shellcheck disable=SC2086
        como_root $INST $GOBJECT || aviso "No se pudo instalar PyGObject: no habrá icono (la sincronización funcionará igual)."
    fi
    if [ -n "$GTK" ]; then   # opcional: icono en bandejas X11 antiguas
        # shellcheck disable=SC2086
        como_root $INST $GTK >/dev/null 2>&1 || true
    fi
    configurar_fuse
}

# FUSE: cargar el módulo ahora y en cada arranque, y comprobar permisos de /dev/fuse
configurar_fuse() {
    [ -e /dev/fuse ] || como_root modprobe fuse 2>/dev/null || aviso "No se pudo cargar el módulo fuse ahora."
    if [ -d /etc/modules-load.d ] && [ ! -e /etc/modules-load.d/fuse.conf ] && [ ! -f /etc/alpine-release ]; then
        como_root sh -c 'echo fuse > /etc/modules-load.d/fuse.conf' && ok "FUSE se cargará en cada arranque."
    elif [ -f /etc/modules ] || [ -f /etc/alpine-release ]; then          # OpenRC / Alpine
        if ! grep -qx fuse /etc/modules 2>/dev/null; then
            como_root sh -c 'echo fuse >> /etc/modules' && ok "FUSE se cargará en cada arranque (/etc/modules)."
        fi
    fi
    if [ -e /dev/fuse ] && { [ ! -r /dev/fuse ] || [ ! -w /dev/fuse ]; }; then
        if grep -q '^fuse:' /etc/group 2>/dev/null; then
            info "Tu usuario no puede usar /dev/fuse: añadiéndolo al grupo «fuse»…"
            if command -v usermod >/dev/null 2>&1; then
                como_root usermod -aG fuse "$(id -un)"
            else
                como_root addgroup "$(id -un)" fuse
            fi && aviso "Cierra sesión y vuelve a entrar para que el cambio de grupo tenga efecto."
        else
            aviso "Tu usuario no tiene permiso sobre /dev/fuse. Pide al administrador que lo permita."
        fi
    fi
}

# Versión de rclone instalada como «mayor.menor» (vacío si no hay)
version_rclone() {
    for r in "$BIN/rclone" "$(command -v rclone 2>/dev/null || true)"; do
        if [ -n "$r" ] && [ -x "$r" ]; then
            "$r" version 2>/dev/null | sed -n '1s/^rclone v\([0-9]*\.[0-9]*\).*/\1/p'
            return 0
        fi
    done
}

version_suficiente() {   # $1 = «mayor.menor»
    [ -n "$1" ] || return 1
    awk -v a="$1" -v b="$VERSION_MINIMA_RCLONE" 'BEGIN {
        split(a, x, "."); split(b, y, ".");
        exit !((x[1] > y[1]) || (x[1] == y[1] && x[2] >= y[2])) }'
}

descargar() {   # $1=url  $2=destino
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        python3 -c 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' "$1" "$2"
    fi
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
    fi
}

# Si la distribución no trae rclone, o trae una versión anterior a la 1.66, ofrecer el
# binario oficial (estático: funciona también con musl/Alpine) en ~/.local/bin,
# comprobando su suma SHA-256 publicada por rclone.
rclone_oficial() {
    actual="$(version_rclone || true)"
    if version_suficiente "$actual"; then
        return 0
    fi
    case "$(uname -m)" in
        x86_64|amd64) arq=amd64 ;;
        aarch64|arm64) arq=arm64 ;;
        armv7*|armv8l) arq=arm-v7 ;;
        armv6*) arq=arm-v6 ;;
        i?86) arq=386 ;;
        *) error "Arquitectura $(uname -m) no soportada automáticamente."; return 1 ;;
    esac
    if [ -n "$actual" ]; then
        printf "Tu rclone (v%s) es anterior a la %s: sin precarga de carpetas ni sincronización robusta.\n" "$actual" "$VERSION_MINIMA_RCLONE"
    else
        printf "rclone no está disponible en tu distribución.\n"
    fi
    printf "¿Descargar el binario oficial de rclone.org a %s? [s/N] " "$BIN"
    read -r resp || resp=n
    case "$resp" in s|S|si|sí|y|Y) ;; *) return 1 ;; esac

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fallo_descarga() {
        error "No se pudo descargar rclone (¿sin conexión?). No se instala nada."
        rm -rf "$tmp"; trap - EXIT INT TERM
        return 1
    }
    descargar "https://downloads.rclone.org/version.txt" "$tmp/version.txt" || { fallo_descarga; return 1; }
    ver="$(sed -n '1s/^rclone \(v[0-9.]*\).*/\1/p' "$tmp/version.txt")"
    [ -n "$ver" ] || { error "No se pudo averiguar la última versión de rclone."; rm -rf "$tmp"; trap - EXIT INT TERM; return 1; }
    zip="rclone-$ver-linux-$arq.zip"
    info "Descargando $zip…"
    descargar "https://downloads.rclone.org/$ver/$zip" "$tmp/$zip" || { fallo_descarga; return 1; }
    descargar "https://downloads.rclone.org/$ver/SHA256SUMS" "$tmp/SHA256SUMS" || { fallo_descarga; return 1; }
    esperado="$(grep " $zip\$" "$tmp/SHA256SUMS" | cut -d' ' -f1 | head -1)"
    obtenido="$(sha256 "$tmp/$zip")"
    if [ -z "$esperado" ] || [ "$esperado" != "$obtenido" ]; then
        error "La suma SHA-256 de la descarga no coincide: NO se instala (descarga dañada o manipulada)."
        rm -rf "$tmp"; trap - EXIT INT TERM
        return 1
    fi
    ok "Suma SHA-256 verificada."
    if command -v unzip >/dev/null 2>&1; then
        (cd "$tmp" && unzip -q "$zip")
    else
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$tmp/$zip" "$tmp"
    fi
    mkdir -p "$BIN"
    cp "$tmp"/rclone-*/rclone "$BIN/rclone"
    chmod 755 "$BIN/rclone"
    rm -rf "$tmp"
    trap - EXIT INT TERM
    ok "rclone $ver instalado en $BIN/rclone"
}

# --------------------------------------------------------------- aplicación
instalar_aplicacion() {
    info "Instalando la aplicación en $DESTINO…"
    mkdir -p "$DESTINO" "$BIN" "$DATA/applications" "$(dirname "$ICONO")"
    cp "$ORIGEN/nubes_rclone.py" "$ORIGEN/nubes_bandeja.py" "$ORIGEN/nubes_sinc.py" "$DESTINO/"
    chmod 755 "$DESTINO/nubes_rclone.py" "$DESTINO/nubes_bandeja.py" "$DESTINO/nubes_sinc.py"
    # Colores y letra del escritorio (opcional: sin él, el aspecto de siempre).
    if [ -f "$ORIGEN/nubes_tema.py" ]; then
        cp "$ORIGEN/nubes_tema.py" "$DESTINO/"
        chmod 644 "$DESTINO/nubes_tema.py"
    fi

    cat > "$BIN/$APP_ID" <<EOF
#!/bin/sh
# Incluye ~/.local/bin para encontrar rclone si se instaló ahí
PATH="\$HOME/.local/bin:\$PATH"
export PATH
exec python3 "$DESTINO/nubes_rclone.py" "\$@"
EOF
    chmod 755 "$BIN/$APP_ID"

    cat > "$ICONO" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect x="4" y="14" width="56" height="42" rx="6" fill="#3b82f6"/>
  <path d="M4 20a6 6 0 0 1 6-6h14l5 6h25a6 6 0 0 1 6 6v0H4z" fill="#2563eb"/>
  <path d="M22 46h22a8 8 0 0 0 1-15.9A11 11 0 0 0 24 32a7 7 0 0 0-2 14z" fill="#fff"/>
</svg>
EOF

    cat > "$LANZADOR" <<EOF
[Desktop Entry]
Type=Application
Name=Lázaro Nubes
GenericName=Gestor de nubes
Comment=Conecta Google Drive, OneDrive y Dropbox como carpetas
Exec=$(exec_desktop "$BIN/$APP_ID")
Icon=$APP_ID
Terminal=false
Categories=Network;FileTransfer;Utility;
Keywords=rclone;nube;cloud;drive;onedrive;dropbox;google;
StartupWMClass=$APP_ID
EOF
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "$DATA/icons/hicolor" 2>/dev/null || true

    # Si ya había inicio automático configurado, apuntarlo al nuevo lanzador
    auto="$CONFIG/autostart/$APP_ID-automontaje.desktop"
    if [ -f "$auto" ]; then
        reemplazar_exec "$auto" "Exec=$(exec_desktop "$BIN/$APP_ID") --montar-auto"
    fi
    ok "Aplicación instalada."
}

# ------------------------------------------- icono del área de notificaciones
instalar_bandeja() {
    if python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' 2>/dev/null; then
        info "Creando el icono del área de notificaciones…"
    else
        aviso "Sin PyGObject no habrá icono, pero la sincronización funcionará igual (sin icono)."
    fi
    mkdir -p "$CONFIG/autostart"
    cat > "$CONFIG/autostart/$APP_ID-bandeja.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Lázaro Nubes (icono de sincronización)
Comment=Icono en el área de notificaciones con el estado de tus nubes
Exec=$(exec_desktop "$BIN/$APP_ID") --bandeja
Icon=$APP_ID
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=8
X-KDE-autostart-after=panel
EOF
    ok "Se iniciará automáticamente al entrar a tu sesión."
    # Reiniciar el icono si ya estaba en marcha (para usar la versión nueva)
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        cerrar_icono
        mkdir -p -m 700 "$CACHE/$APP_ID"
        nohup "$BIN/$APP_ID" --bandeja >> "$CACHE/$APP_ID/bandeja.log" 2>&1 &
        if python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then
            ok "Icono iniciado: búscalo en el área de notificaciones (junto al reloj)."
        else
            ok "Sincronización iniciada (sin icono: falta PyGObject)."
        fi
        case "${XDG_CURRENT_DESKTOP:-}" in
            *GNOME*) aviso "GNOME: si no ves el icono, instala la extensión «AppIndicator and KStatusNotifierItem Support»." ;;
        esac
    fi
    # Gestores de ventanas sin inicio automático XDG (i3, Sway, Openbox, dwm…)
    if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
        aviso "Tu sesión no indica un escritorio: si usas un gestor de ventanas (i3, Sway, Openbox…),"
        aviso "añade estas líneas a su archivo de arranque:"
        printf '      %s --montar-auto\n      %s --bandeja\n' "$BIN/$APP_ID" "$BIN/$APP_ID"
    fi
}

activar_equipo_compartido() {
    python3 - "$DESTINO" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import nubes_rclone as n
# Igual que el botón «Equipo compartido…»: sin montaje automático en este modo
n.modificar_ajustes(lambda a: a.update(equipo_compartido=True, automontaje=[]))
n.actualizar_autoarranque(n.cargar_ajustes())
PYEOF
    ok "Modo «equipo compartido» activado: cada sesión empezará sin cuentas conectadas."
}

comprobar() {
    info "Comprobación final:"
    v="$(version_rclone || true)"
    if [ -z "$v" ]; then error "rclone no encontrado"
    elif version_suficiente "$v"; then ok "rclone v$v"
    else aviso "rclone v$v (se recomienda $VERSION_MINIMA_RCLONE o posterior)"; fi
    if command -v fusermount3 >/dev/null 2>&1 || command -v fusermount >/dev/null 2>&1; then ok "FUSE"; else error "FUSE (fuse3) no encontrado"; fi
    if [ -r /dev/fuse ] && [ -w /dev/fuse ]; then ok "/dev/fuse"
    elif [ -e /dev/fuse ]; then aviso "/dev/fuse existe pero tu usuario no puede usarlo"
    else aviso "/dev/fuse no existe: ejecuta «sudo modprobe fuse»"; fi
    if python3 -c 'import tkinter' 2>/dev/null; then ok "Python + Tkinter"; else error "Falta Tkinter para Python 3"; fi
    if python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then ok "PyGObject (icono del área de notificaciones)"; else aviso "Falta PyGObject: sin icono (la sincronización funciona igual)"; fi
    case ":$PATH:" in
        *":$BIN:"*) ;;
        *) aviso "$BIN no está en tu PATH; ábrela desde el menú o con: $BIN/$APP_ID" ;;
    esac
    echo
    ok "Listo. Busca «Lázaro Nubes» en el menú de aplicaciones o ejecuta: $APP_ID"
}

DEPENDENCIAS=1
COMPARTIDO=0
for opcion in "$@"; do
    case "$opcion" in
        --desinstalar|--uninstall) desinstalar ;;
        --sin-dependencias) DEPENDENCIAS=0 ;;
        --equipo-compartido) COMPARTIDO=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) error "Opción desconocida: $opcion"; exit 2 ;;
    esac
done
if [ "$DEPENDENCIAS" -eq 1 ]; then
    instalar_dependencias || aviso "Algunas dependencias no se pudieron instalar."
    rclone_oficial || true
fi
instalar_aplicacion
if [ "$COMPARTIDO" -eq 1 ]; then activar_equipo_compartido; fi
instalar_bandeja
comprobar
