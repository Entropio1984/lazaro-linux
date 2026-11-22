#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lázaro Nubes - Interfaz gráfica sencilla para rclone en Linux.

Permite conectar Google Drive, OneDrive y Dropbox, montarlos como carpetas
y añadirlos a la barra lateral del explorador de archivos (Nautilus, Nemo,
Caja, Thunar, PCManFM, Dolphin...).

Solo usa la biblioteca estándar de Python + Tkinter, por lo que funciona en
cualquier distribución (Debian/Ubuntu, Fedora, Arch, openSUSE, Void, Alpine...).

Uso:
    nubes_rclone.py                 abre la interfaz gráfica
    nubes_rclone.py --montar-auto   monta las nubes marcadas para el inicio
                                    de sesión (lo usa el autoarranque)
    nubes_rclone.py --desmontar-todo
    nubes_rclone.py --bandeja       inicia el icono del área de notificaciones
                                    (sincronización de carpetas locales)
    nubes_rclone.py --sincronizar-servicio
                                    sincroniza sin icono (servidores, sistemas mínimos)
"""

import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse

APP_NOMBRE = "Lázaro Nubes"
APP_ID = "nubes-rclone"
VERSION = "1.0"

HOME = os.path.expanduser("~")
XDG_CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
XDG_CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
XDG_DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")

DIR_CONFIG = os.path.join(XDG_CONFIG, APP_ID)
ARCHIVO_AJUSTES = os.path.join(DIR_CONFIG, "ajustes.json")
DIR_LOGS = os.path.join(XDG_CACHE, APP_ID)


def _dir_ejecucion():
    """Sockets, bloqueos y peticiones van en $XDG_RUNTIME_DIR (privado del usuario,
    en memoria y se vacía al cerrar sesión). Si no existe, en la caché privada."""
    run = os.environ.get("XDG_RUNTIME_DIR")
    try:
        if run and os.path.isdir(run) and os.stat(run).st_uid == os.getuid():
            return os.path.join(run, APP_ID)
    except OSError:
        pass
    return os.path.join(DIR_LOGS, "ejecucion")


DIR_EJEC = _dir_ejecucion()


def asegurar_dir(ruta):
    """Crea la carpeta (y la deja) con permisos 0700: solo el usuario puede entrar."""
    os.makedirs(ruta, mode=0o700, exist_ok=True)
    try:
        os.chmod(ruta, 0o700)
    except OSError:
        pass
    return ruta
ARCHIVO_AUTOSTART = os.path.join(XDG_CONFIG, "autostart", APP_ID + "-automontaje.desktop")
MARCADORES_GTK = os.path.join(XDG_CONFIG, "gtk-3.0", "bookmarks")
MARCADORES_KDE = os.path.join(XDG_DATA, "user-places.xbel")
MARCADORES_GTK2 = os.path.join(HOME, ".gtk-bookmarks")   # GTK2 heredado (solo si existe)

# --------------------------------------------------------------------------
# Información de cada proveedor (textos explicativos para el usuario)
# --------------------------------------------------------------------------
PROVEEDORES = {
    "drive": {
        "titulo": "Google Drive",
        "nombre_sugerido": "GoogleDrive",
        "descripcion": (
            "Conecta tu cuenta de Google (Gmail o Google Workspace).\n\n"
            "Al pulsar «Conectar» se abrirá tu navegador para que inicies sesión "
            "en Google y autorices a rclone. Es posible que Google muestre el aviso "
            "«Google no ha verificado esta aplicación»: es normal con rclone. Pulsa "
            "«Configuración avanzada» → «Ir a rclone» para continuar.\n\n"
            "Los documentos de Google (Docs, Hojas de cálculo, Presentaciones) se "
            "verán como archivos de Office (.docx, .xlsx, .pptx)."
        ),
    },
    "onedrive": {
        "titulo": "Microsoft OneDrive",
        "nombre_sugerido": "OneDrive",
        "descripcion": (
            "Conecta tu cuenta de Microsoft (Outlook/Hotmail, OneDrive Personal "
            "o una cuenta de trabajo/escuela de Microsoft 365).\n\n"
            "Al pulsar «Conectar» se abrirá tu navegador para que inicies sesión "
            "en Microsoft y aceptes los permisos. Si tu cuenta tiene varias "
            "unidades, se usará la principal (tu OneDrive personal).\n\n"
            "Cuentas de colegio, universidad o empresa: si Microsoft pide la aprobación "
            "de un administrador, elige «Permisos: Mínimos» y vuelve a intentarlo."
        ),
    },
    "dropbox": {
        "titulo": "Dropbox",
        "nombre_sugerido": "Dropbox",
        "descripcion": (
            "Conecta tu cuenta de Dropbox (gratuita, Plus o Business).\n\n"
            "Al pulsar «Conectar» se abrirá tu navegador para que inicies sesión "
            "en Dropbox y pulses «Permitir».\n\n"
            "Nota: Dropbox limita la cantidad de peticiones por segundo; si "
            "copias miles de archivos pequeños puede ir algo más lento."
        ),
    },
}

TIPOS_LEGIBLES = {k: v["titulo"] for k, v in PROVEEDORES.items()}

MSG_SOLO_LECTURA_SIN_SINC = (
    "Esta conexión tiene permisos de SOLO LECTURA, así que no puede sincronizarse: la "
    "sincronización necesita subir a la nube lo que cambies en la carpeta local.\n\n"
    "Usa «Montar como carpeta», o vuelve a conectar la cuenta con permisos de lectura y escritura.")
MSG_COMPARTIDO_SIN_SINC = (
    "El modo «equipo compartido» está activado: la sincronización con carpeta local no está "
    "disponible, porque la copia de tus archivos quedaría al alcance de la siguiente persona.\n\n"
    "Usa «Montar como carpeta».")

# Opción de permisos elegida por defecto. En OneDrive, «Mínimos»: las cuentas de
# colegios y secretarías suelen bloquear los permisos completos.
PERMISO_DEFECTO = {"onedrive": 1}

# Permisos que se piden al servicio: (etiqueta, parámetros de rclone, explicación).
# Los «mínimos» piden mucho menos acceso; en cuentas institucionales (educación,
# empresa) a veces permiten conectar sin aprobación del administrador y, si no,
# la facilitan porque el administrador ve que solo se accede a tus propios archivos.
PERMISOS = {
    "drive": [
        ("Acceso completo (leer y escribir)", ["scope=drive"],
         "Ves y modificas todo tu Google Drive, como una carpeta normal."),
        ("Solo lectura", ["scope=drive.readonly"],
         "Ves todo tu Drive pero no se puede modificar ni borrar nada desde este equipo."),
        ("Mínimos: solo lo creado desde este equipo", ["scope=drive.file"],
         "Permiso más pequeño de Google. Solo verás los archivos y carpetas que subas desde "
         "aquí, no los que ya tenías. Útil como copia de seguridad en cuentas institucionales."),
    ],
    "onedrive": [
        ("Acceso completo (incluye SharePoint)", [],
         "Tus archivos, los compartidos contigo y los sitios de SharePoint. En cuentas de "
         "educación o empresa suele requerir aprobación del administrador."),
        ("Mínimos: solo mis archivos (institucional)", ["access_scopes=Files.Read Files.ReadWrite offline_access"],
         "Solo tu propio OneDrive (leer y escribir). No incluye lo compartido contigo ni "
         "SharePoint. Recomendado para cuentas de colegios, universidades y empresas."),
        ("Mínimos y solo lectura", ["access_scopes=Files.Read offline_access"],
         "Solo puedes ver y descargar tus propios archivos; no se modifica nada en OneDrive."),
    ],
}

# Exploradores de archivos conocidos (ejecutable -> nombre legible)
EXPLORADORES = [
    ("nautilus", "Nautilus / Archivos (GNOME)"),
    ("dolphin", "Dolphin (KDE)"),
    ("nemo", "Nemo (Cinnamon)"),
    ("caja", "Caja (MATE)"),
    ("thunar", "Thunar (XFCE)"),
    ("pcmanfm-qt", "PCManFM-Qt (LXQt)"),
    ("pcmanfm", "PCManFM (LXDE)"),
    ("spacefm", "SpaceFM"),
    ("index", "Index (Maui)"),
    ("cosmic-files", "Archivos de COSMIC"),
]

# Paquetes por gestor de paquetes (para el mensaje de ayuda)
COMANDOS_INSTALACION = {
    "apk": "sudo apk add rclone fuse3 python3 python3-tkinter py3-gobject3 xdg-utils && sudo modprobe fuse",
    "apt": "sudo apt install rclone fuse3 python3 python3-tk python3-gi gir1.2-gtk-3.0 xdg-utils",
    "dnf": "sudo dnf install rclone fuse3 python3 python3-tkinter python3-gobject xdg-utils",
    "yum": "sudo yum install rclone fuse3 python3 python3-tkinter python3-gobject xdg-utils",
    "pacman": "sudo pacman -S --needed rclone fuse3 python tk python-gobject xdg-utils",
    "zypper": "sudo zypper install rclone fuse3 python3 python3-tk python3-gobject xdg-utils",
    "xbps-install": "sudo xbps-install -S rclone fuse3 python3 python3-tkinter python3-gobject xdg-utils",
    "eopkg": "sudo eopkg install rclone fuse3 python3 python3-tkinter python3-gobject xdg-utils",
    "emerge": "sudo emerge --ask net-misc/rclone sys-fs/fuse:3 dev-python/pygobject x11-misc/xdg-utils  (Python con USE=tk)",
    "nix-env": "nix-env -iA nixpkgs.rclone nixpkgs.fuse3 nixpkgs.python3Full nixpkgs.python3Packages.pygobject3",
}


# ==========================================================================
#  LÓGICA (sin interfaz gráfica, usable también desde la línea de órdenes)
# ==========================================================================

def cargar_ajustes():
    ajustes = {"carpeta_base": os.path.join(HOME, "Nubes"), "automontaje": [],
               "sincronizacion": {}, "pausado": False}
    try:
        with open(ARCHIVO_AJUSTES, "r", encoding="utf-8") as f:
            ajustes.update(json.load(f))
    except (OSError, ValueError):
        pass
    return ajustes


def guardar_ajustes(ajustes):
    asegurar_dir(DIR_CONFIG)
    tmp = ARCHIVO_AJUSTES + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(ajustes, f, indent=2, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, ARCHIVO_AJUSTES)


def modificar_ajustes(funcion):
    """Lee, modifica y guarda los ajustes bajo un bloqueo compartido, para que la
    ventana y el icono de la bandeja no se pisen los cambios. Devuelve los ajustes."""
    import fcntl
    asegurar_dir(DIR_CONFIG)
    with open(ARCHIVO_AJUSTES + ".lock", "a") as bloqueo:
        fcntl.flock(bloqueo, fcntl.LOCK_EX)
        try:
            ajustes = cargar_ajustes()
            funcion(ajustes)
            guardar_ajustes(ajustes)
        finally:
            fcntl.flock(bloqueo, fcntl.LOCK_UN)
    return ajustes


def rclone_bin():
    # El binario oficial que descarga el instalador (en ~/.local/bin) tiene prioridad:
    # solo se descarga cuando el de la distribución falta o es demasiado antiguo.
    propio = os.path.join(HOME, ".local", "bin", "rclone")
    if os.access(propio, os.X_OK):
        return propio
    encontrado = shutil.which("rclone")
    if encontrado:
        return encontrado
    if os.access("/usr/local/bin/rclone", os.X_OK):
        return "/usr/local/bin/rclone"
    return None


def fusermount_bin():
    return shutil.which("fusermount3") or shutil.which("fusermount")


def version_rclone():
    rc = rclone_bin()
    if not rc:
        return None
    try:
        salida = subprocess.run([rc, "version"], capture_output=True, text=True, timeout=15).stdout
        return salida.splitlines()[0].strip() if salida else "desconocida"
    except (OSError, subprocess.SubprocessError):
        return None


def detectar_distribucion():
    """Devuelve (nombre legible, gestor de paquetes)."""
    nombre = "Linux"
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            datos = dict(
                linea.rstrip("\n").split("=", 1) for linea in f if "=" in linea
            )
        nombre = datos.get("PRETTY_NAME", datos.get("NAME", "Linux")).strip('"')
    except OSError:
        pass
    for gestor in ("apk", "apt", "dnf", "yum", "pacman", "zypper",
                   "xbps-install", "eopkg", "emerge", "nix-env"):
        if shutil.which(gestor):
            return nombre, gestor
    return nombre, None


def explorador_predeterminado():
    """Explorador que el usuario tiene configurado para abrir carpetas (xdg-mime)."""
    if not shutil.which("xdg-mime"):
        return None
    codigo, salida = ejecutar(["xdg-mime", "query", "default", "inode/directory"], timeout=10)
    salida = salida.strip()
    return salida[:-len(".desktop")] if codigo == 0 and salida.endswith(".desktop") else None


def detectar_exploradores():
    encontrados = [(exe, nombre) for exe, nombre in EXPLORADORES if shutil.which(exe)]
    predeterminado = explorador_predeterminado()
    if predeterminado:
        # Cualquier explorador configurado por el usuario, aunque no esté en la lista
        encontrados.insert(0, (predeterminado, "Predeterminado: " + predeterminado))
    return encontrados


def ejecutar(args, timeout=60):
    """Ejecuta una orden y devuelve (codigo, salida combinada)."""
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "La orden tardó demasiado en responder."
    except OSError as e:
        return 127, str(e)


def listar_remotos():
    """Devuelve lista de (nombre, tipo) de las conexiones configuradas en rclone."""
    rc = rclone_bin()
    if not rc:
        return []
    codigo, salida = ejecutar([rc, "listremotes", "--long"], timeout=20)
    remotos = []
    if codigo != 0:
        return remotos
    for linea in salida.splitlines():
        m = re.match(r"^(.+?):\s+(\S+)\s*$", linea)
        if m:
            remotos.append((m.group(1), m.group(2)))
    return remotos


def nombre_valido(nombre):
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,40}", nombre))


def punto_montaje(nombre, ajustes=None):
    ajustes = ajustes or cargar_ajustes()
    return os.path.join(os.path.expanduser(ajustes["carpeta_base"]), nombre)


def _decodificar_mounts(texto):
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), texto)


def montajes_actuales():
    """Devuelve {ruta: tipo_fs} leyendo /proc/mounts (funciona con BusyBox)."""
    resultado = {}
    try:
        with open("/proc/mounts", encoding="utf-8", errors="replace") as f:
            for linea in f:
                partes = linea.split()
                if len(partes) >= 3:
                    resultado[_decodificar_mounts(partes[1])] = partes[2]
    except OSError:
        pass
    return resultado


def esta_montado(ruta):
    montajes = montajes_actuales()
    return ruta in montajes or os.path.realpath(ruta) in montajes


def montaje_roto(ruta):
    """True si hay un montaje FUSE «colgado» (Transport endpoint is not connected)."""
    if not esta_montado(ruta):
        return False
    try:
        os.listdir(ruta)
        return False
    except OSError:
        return True


def desmontar(ruta):
    """Desmonta una carpeta. Devuelve (ok, mensaje)."""
    if not esta_montado(ruta):
        return True, "La carpeta no estaba montada."
    fm = fusermount_bin()
    intentos = []
    if fm:
        intentos += [[fm, "-u", ruta], [fm, "-uz", ruta]]
    intentos += [["umount", ruta]]
    ultimo = ""
    for orden in intentos:
        codigo, salida = ejecutar(orden, timeout=30)
        if codigo == 0 or not esta_montado(ruta):
            return True, "Desmontado correctamente."
        ultimo = salida
    return False, ("No se pudo desmontar. Cierra las ventanas o programas que estén "
                   "usando archivos de esa carpeta e inténtalo de nuevo.\n\n" + ultimo)


# Servidor de cada servicio, para comprobar si se llega a él por IPv6
HOST_SERVICIO = {"drive": "www.googleapis.com", "onedrive": "graph.microsoft.com",
                 "dropbox": "api.dropboxapi.com"}
_cache_ipv4 = {}


def forzar_ipv4(tipo):
    """True si el equipo tiene IPv6 pero el servicio no responde por IPv6 y sí por IPv4.
    En esas redes cada conexión pierde tiempo intentando IPv6 y algunas se quedan colgadas."""
    host = HOST_SERVICIO.get(tipo)
    if not host:
        return False
    guardado = _cache_ipv4.get(host)
    if guardado and time.time() - guardado[0] < 600:      # se repite cada 10 minutos
        return guardado[1]
    import socket

    def llega(familia):
        try:
            direcciones = socket.getaddrinfo(host, 443, familia, socket.SOCK_STREAM)
        except OSError:
            return None                      # el servicio no tiene direcciones de ese tipo
        # Se prueban varias direcciones: en algunas redes ciertos servidores no responden
        for *_resto, direccion in direcciones[:4]:
            s = socket.socket(familia, socket.SOCK_STREAM)
            s.settimeout(2)
            try:
                s.connect(direccion)
                return True
            except OSError:
                pass
            finally:
                s.close()
        return False
    resultado = llega(socket.AF_INET6) is False and llega(socket.AF_INET) is True
    _cache_ipv4[host] = (time.time(), resultado)
    return resultado


LIMITES_VELOCIDAD = [("Sin límite", ""), ("1 MB/s", "1M"), ("5 MB/s", "5M"), ("10 MB/s", "10M")]


def opciones_red(tipo, bwlimit=None):
    """Opciones de red comunes a montar y sincronizar: si una petición se queda
    atascada se reintenta a los pocos segundos (por defecto rclone espera 5 minutos)."""
    opciones = ["--contimeout", "15s", "--timeout", "30s", "--low-level-retries", "10"]
    if bwlimit:
        opciones += ["--bwlimit", bwlimit]   # para no saturar la red (p. ej. la del colegio)
    if tipo in ("onedrive", "dropbox"):
        # Con HTTP/2 todas las peticiones van por una sola conexión: si esa conexión cae
        # en un servidor con pérdida de paquetes, todos los reintentos fallan igual.
        # Con HTTP/1.1 cada reintento abre otra conexión. (Google Drive ya lo hace así.)
        opciones += ["--disable-http2"]
    if forzar_ipv4(tipo):
        opciones += ["--bind", "0.0.0.0"]    # usar solo IPv4
    return opciones


def socket_control(nombre):
    return os.path.join(asegurar_dir(DIR_EJEC), nombre + ".sock")


def orden_precarga(sock, tipo):
    """En OneDrive solo se precarga la raíz: recorrer todas las carpetas compite con lo
    que abre el usuario en el explorador (en redes lentas hacia Microsoft se notó mucho)."""
    orden = [rclone_bin(), "rc", "--unix-socket", sock, "vfs/refresh", "_async=true"]
    if tipo != "onedrive":
        orden.append("recursive=true")
    return orden


def precargar_carpetas(nombre, tipo=""):
    """Pide al montaje que lea en segundo plano el listado de las carpetas,
    para que al abrirlas en el explorador aparezcan al instante."""
    sock = socket_control(nombre)
    if not os.path.exists(sock) or not rclone_bin():
        return
    try:
        subprocess.Popen(orden_precarga(sock, tipo),
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def montar(nombre, ajustes=None, espera=60):
    """Monta la nube `nombre` en su carpeta. Devuelve (ok, mensaje)."""
    ajustes = ajustes or cargar_ajustes()
    rc = rclone_bin()
    if not rc:
        return False, "rclone no está instalado."
    if not fusermount_bin():
        return False, ("Falta FUSE (fusermount3). Instala el paquete «fuse3» de tu "
                       "distribución para poder montar nubes como carpetas.")
    if not os.path.exists("/dev/fuse"):
        return False, ("No existe /dev/fuse. El módulo del kernel FUSE no está cargado.\n"
                       "Ejecuta: sudo modprobe fuse\n"
                       "(En Alpine, añade «fuse» a /etc/modules para que cargue siempre).")
    ruta = punto_montaje(nombre, ajustes)
    if montaje_roto(ruta):
        desmontar(ruta)
    if esta_montado(ruta):
        return True, "Ya estaba montada en " + ruta
    os.makedirs(ruta, exist_ok=True)
    if os.listdir(ruta):
        return False, ("La carpeta %s no está vacía. rclone necesita una carpeta vacía "
                       "para montar la nube. Mueve su contenido a otro sitio." % ruta)
    asegurar_dir(DIR_LOGS)
    log = os.path.join(DIR_LOGS, nombre + ".log")
    try:
        if os.path.getsize(log) > 2 * 1024 * 1024:     # rotar el registro de montaje
            os.replace(log, log + ".1")
    except OSError:
        pass
    tipo = dict(listar_remotos()).get(nombre, "")
    orden = [
        rc, "mount", nombre + ":", ruta,
        "--vfs-cache-mode", "full",          # permite abrir/editar archivos con cualquier programa
        "--vfs-cache-max-age", "24h",
        # Límite de espacio en disco para los archivos abiertos (se borran los más antiguos)
        "--vfs-cache-max-size", str(ajustes.get("cache_max", "2G")),
        # Recordar el contenido de las carpetas 24 h: Drive, OneDrive y Dropbox avisan
        # de los cambios cada minuto (--poll-interval), así no se vuelve a pedir todo.
        "--dir-cache-time", "24h",
        "--poll-interval", "1m",
        "--volname", nombre,
        "--log-file", log,
        "--log-level", "NOTICE",
    ] + opciones_red(tipo, ajustes.get("bwlimit") or None)
    sock = socket_control(nombre)
    # Linux limita la ruta de un socket a 108 bytes: si es más larga, se monta sin él
    if version_tupla() >= (1, 66) and len(sock.encode()) < 100:
        # Canal de control local (solo accesible por este usuario) para precargar carpetas
        try:
            os.remove(sock)
        except OSError:
            pass
        orden += ["--rc", "--rc-addr", "unix://" + sock, "--rc-no-auth"]
    try:
        with open(log, "a", encoding="utf-8") as f:
            f.write("\n==== %s montando %s en %s ====\n" % (time.strftime("%F %T"), nombre, ruta))
        proc = subprocess.Popen(orden, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        return False, "No se pudo ejecutar rclone: %s" % e

    limite = time.time() + espera
    while time.time() < limite:
        if esta_montado(ruta):
            time.sleep(0.5)
            precargar_carpetas(nombre, tipo)
            return True, "Montada en " + ruta
        if proc.poll() is not None:
            break
        time.sleep(0.4)
    if proc.poll() is None and not esta_montado(ruta):
        proc.terminate()
    return False, "rclone no pudo montar la nube. Últimas líneas del registro:\n\n" + leer_final(log)


def leer_final(ruta, lineas=12):
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            return "".join(f.readlines()[-lineas:]).strip() or "(registro vacío)"
    except OSError:
        return "(sin registro)"


PUERTO_OAUTH = 53682   # rclone recibe aquí la respuesta del inicio de sesión


def puerto_oauth_ocupado():
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", PUERTO_OAUTH))
        return False
    except OSError:
        return True
    finally:
        s.close()


def procesos_config_rclone():
    """PIDs de «rclone config create/reconnect» del usuario que siguen en marcha
    (p. ej. un intento anterior cuyo navegador se cerró sin iniciar sesión)."""
    pids = []
    for d in os.listdir("/proc"):
        if not d.isdigit() or int(d) == os.getpid():
            continue
        try:
            if os.stat("/proc/" + d).st_uid != os.getuid():
                continue
            with open("/proc/%s/cmdline" % d, "rb") as f:
                partes = f.read().split(b"\0")
        except OSError:
            continue
        if (len(partes) > 2 and os.path.basename(partes[0]) == b"rclone"
                and partes[1] == b"config" and partes[2] in (b"create", b"reconnect", b"update")):
            pids.append(int(d))
    return pids


def cancelar_procesos_config(pids, espera=5):
    import signal
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    limite = time.time() + espera
    while time.time() < limite and puerto_oauth_ocupado():
        time.sleep(0.2)
    return not puerto_oauth_ocupado()


def aplicar_bwlimit(valor):
    """Cambia en vivo el límite de velocidad de las nubes montadas (por su canal de control).
    Las sincronizaciones lo aplican a partir de la siguiente."""
    rc = rclone_bin()
    if not rc or not os.path.isdir(DIR_EJEC):
        return
    for archivo in os.listdir(DIR_EJEC):
        if archivo.endswith(".sock"):
            ejecutar([rc, "rc", "--unix-socket", os.path.join(DIR_EJEC, archivo),
                      "core/bwlimit", "rate=" + (valor or "off")], timeout=15)


def eliminar_remoto(nombre):
    rc = rclone_bin()
    if not rc:
        return 127, "rclone no está instalado."
    return ejecutar([rc, "config", "delete", nombre], timeout=30)


def archivo_config_rclone():
    """Ruta de rclone.conf («rclone config file»), o None."""
    rc = rclone_bin()
    if not rc:
        return None
    codigo, salida = ejecutar([rc, "config", "file"], timeout=20)
    if codigo != 0:
        return None
    lineas = [l.strip() for l in salida.splitlines() if l.strip()]
    return lineas[-1] if lineas and os.path.isabs(lineas[-1]) else None


def guardar_secreto(nombre, secreto):
    """Guarda client_secret en la sección [nombre] de rclone.conf sin pasarlo por la
    línea de órdenes (ahí cualquier usuario del equipo lo vería en /proc).
    Devuelve (codigo, mensaje) como ejecutar()."""
    ruta = archivo_config_rclone()
    try:
        with open(ruta or "", encoding="utf-8") as f:
            contenido = f.read()
    except (OSError, ValueError):
        contenido = None
    if contenido is None:
        return 1, "No se pudo leer la configuración de rclone."
    if contenido.lstrip().startswith("# Encrypted rclone configuration"):
        # Configuración cifrada: solo rclone puede escribirla
        return ejecutar([rclone_bin(), "config", "update", nombre,
                         "client_secret=" + secreto,
                         "config_refresh_token=false", "--no-output"], timeout=20)
    lineas = contenido.splitlines()
    inicio = None
    for i, l in enumerate(lineas):
        if l.strip() == "[%s]" % nombre:
            inicio = i
            break
    if inicio is None:
        return 1, "No se encontró la conexión «%s» en rclone.conf." % nombre
    fin = len(lineas)
    for i in range(inicio + 1, len(lineas)):
        if lineas[i].strip().startswith("["):
            fin = i
            break
    seccion = [l for l in lineas[inicio + 1:fin]
               if not re.match(r"\s*client_secret\s*=", l)]
    # Tras la última línea con datos de la sección (antes de las líneas en blanco)
    pos = len(seccion)
    while pos > 0 and not seccion[pos - 1].strip():
        pos -= 1
    seccion.insert(pos, "client_secret = " + secreto)
    nuevas = lineas[:inicio + 1] + seccion + lineas[fin:]
    try:
        escribir_atomico(ruta, "\n".join(nuevas) + "\n", privado=True)
    except OSError as e:
        return 1, str(e)
    return 0, ""


def permisos_solo_lectura(nombre):
    """True si la conexión se creó con permisos de solo lectura (no admite sincronizar)."""
    rc = rclone_bin()
    if not rc:
        return False
    codigo, salida = ejecutar([rc, "config", "show", nombre], timeout=20)
    if codigo != 0:
        return False
    valores = dict(re.findall(r"^(scope|access_scopes)\s*=\s*(.*)$", salida, re.M))
    if "scope" in valores:
        return "readonly" in valores["scope"]
    if "access_scopes" in valores:
        return "ReadWrite" not in valores["access_scopes"]
    return False


def espacio_remoto(nombre):
    """Devuelve texto con el espacio usado/libre."""
    rc = rclone_bin()
    if not rc:
        return "rclone no está instalado."
    codigo, salida = ejecutar([rc, "about", nombre + ":", "--json"], timeout=60)
    if codigo != 0:
        return "No se pudo consultar el espacio:\n" + salida
    try:
        datos = json.loads(salida[salida.index("{"):])
    except ValueError:
        return salida
    nombres = {"total": "Total", "used": "Usado", "free": "Libre",
               "trashed": "En la papelera", "other": "Otros servicios"}
    lineas = ["%s: %s" % (nombres.get(k, k), formato_bytes(v)) for k, v in datos.items()]
    return "\n".join(lineas) or "El servicio no informa del espacio."


def formato_bytes(n):
    n = float(n)
    for unidad in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unidad == "TB":
            return ("%.0f %s" if unidad == "B" else "%.1f %s") % (n, unidad)
        n /= 1024


# ---------------------- Integración con exploradores ----------------------

def _uri(ruta):
    return "file://" + urllib.parse.quote(ruta)


def escribir_atomico(archivo, contenido, privado=False):
    """Escribe el archivo entero de una vez (temporal + os.replace): si se corta
    la luz a la mitad, queda el archivo de antes, no uno a medias."""
    tmp = "%s.%d.tmp" % (archivo, os.getpid())
    try:
        modo = os.stat(archivo).st_mode & 0o777
    except OSError:
        modo = 0o600
    try:
        # Nace privado (0600) y recién al final toma el permiso del original (o
        # el pedido): nunca hay un momento en que otro usuario pueda leerlo.
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(contenido)
            f.flush()
            os.fsync(f.fileno())
        if privado:
            modo = 0o600
        os.chmod(tmp, modo)
        os.replace(tmp, archivo)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _marcador_lineas(archivo, uri, titulo=None):
    """Añade (titulo dado) o quita (titulo None) una línea «uri título» de un archivo
    de marcadores GTK. Devuelve True si el archivo quedó bien."""
    try:
        lineas = []
        if os.path.exists(archivo):
            with open(archivo, encoding="utf-8") as f:
                lineas = f.read().splitlines()
        if titulo is not None:
            # Si ya está, no se toca: así no cambia el orden de los marcadores del usuario
            nuevas = lineas if any(l.split(" ", 1)[0] == uri for l in lineas) \
                else lineas + ["%s %s" % (uri, titulo)]
        else:
            nuevas = [l for l in lineas if l.split(" ", 1)[0] != uri]
        if nuevas != lineas:
            escribir_atomico(archivo, "\n".join(nuevas) + ("\n" if nuevas else ""))
        return True
    except OSError:
        return False


def anadir_marcador(ruta, titulo):
    """Añade la carpeta a la barra lateral de los exploradores GTK y de KDE."""
    hechos = []
    if os.path.exists(MARCADORES_GTK2):                  # exploradores GTK2 antiguos
        _marcador_lineas(MARCADORES_GTK2, _uri(ruta), titulo)
    # GTK: Nautilus, Nemo, Caja, Thunar, PCManFM y los diálogos «Abrir archivo» GTK
    try:
        os.makedirs(os.path.dirname(MARCADORES_GTK), exist_ok=True)
    except OSError:
        pass
    if _marcador_lineas(MARCADORES_GTK, _uri(ruta), titulo):
        hechos.append("GTK")
    # KDE: Dolphin y diálogos de Qt/KDE (solo si el archivo ya existe → KDE en uso)
    if os.path.exists(MARCADORES_KDE) or shutil.which("dolphin"):
        try:
            _anadir_marcador_kde(ruta, titulo)
            hechos.append("KDE")
        except OSError:
            pass
    return hechos


def _anadir_marcador_kde(ruta, titulo):
    uri = _uri(ruta)
    if os.path.exists(MARCADORES_KDE):
        with open(MARCADORES_KDE, encoding="utf-8") as f:
            contenido = f.read()
    else:
        os.makedirs(os.path.dirname(MARCADORES_KDE), exist_ok=True)
        contenido = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xbel>\n'
                     '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"'
                     ' xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"'
                     ' xmlns:kdepriv="http://www.kde.org/kdepriv">\n</xbel>\n')
    if 'href="%s"' % uri in contenido:
        return
    esc = lambda s: (s.replace("&", "&amp;").replace("<", "&lt;")
                     .replace(">", "&gt;").replace('"', "&quot;"))
    bloque = (
        ' <bookmark href="%s">\n'
        '  <title>%s</title>\n'
        '  <info>\n'
        '   <metadata owner="http://freedesktop.org">\n'
        '    <bookmark:icon name="folder-cloud"/>\n'
        '   </metadata>\n'
        '   <metadata owner="http://www.kde.org">\n'
        '    <ID>%s-%s</ID>\n'
        '   </metadata>\n'
        '  </info>\n'
        ' </bookmark>\n' % (esc(uri), esc(titulo), APP_ID, esc(titulo))
    )
    pos = contenido.rfind("</xbel>")
    if pos == -1:
        return
    contenido = contenido[:pos] + bloque + contenido[pos:]
    escribir_atomico(MARCADORES_KDE, contenido)


def quitar_marcador(ruta):
    uri = _uri(ruta)
    if os.path.exists(MARCADORES_GTK2):
        _marcador_lineas(MARCADORES_GTK2, uri)
    if os.path.exists(MARCADORES_GTK):
        _marcador_lineas(MARCADORES_GTK, uri)
    if os.path.exists(MARCADORES_KDE):
        try:
            with open(MARCADORES_KDE, encoding="utf-8") as f:
                contenido = f.read()
            # KDE puede añadir atributos (added=, modified=...) a la etiqueta
            patron = r'[ \t]*<bookmark\b[^>]*\bhref="%s"[^>]*>.*?</bookmark>\n?' % re.escape(uri)
            nuevo = re.sub(patron, "", contenido, flags=re.S)
            if nuevo != contenido:
                escribir_atomico(MARCADORES_KDE, nuevo)
        except OSError:
            pass


def abrir_url(url):
    """Abre un enlace web en el navegador (nunca con un explorador de archivos)."""
    for orden in (["xdg-open", url], ["gio", "open", url]):
        if shutil.which(orden[0]):
            try:
                subprocess.Popen(orden, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                return True
            except OSError:
                continue
    import webbrowser
    return webbrowser.open(url)


def abrir_en_explorador(ruta):
    """Abre la carpeta con el explorador predeterminado. Devuelve (ok, mensaje)."""
    candidatos = []
    if shutil.which("xdg-open"):
        candidatos.append(["xdg-open", ruta])
    if shutil.which("gio"):
        candidatos.append(["gio", "open", ruta])
    for exe, _ in EXPLORADORES:
        if shutil.which(exe):
            candidatos.append([exe, ruta])
    for orden in candidatos:
        try:
            subprocess.Popen(orden, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
            return True, ""
        except OSError:
            continue
    return False, ("No se encontró ningún explorador de archivos. Instala «xdg-utils» "
                   "o un explorador como Thunar o PCManFM.\nLa carpeta es: " + ruta)


# ---------------------------- Autoarranque ---------------------------------

def _comillas_desktop(arg):
    """Escapa un argumento para la línea Exec de un archivo .desktop."""
    if re.fullmatch(r"[A-Za-z0-9_./=-]+", arg):
        return arg
    return '"' + re.sub(r'(["`$\\])', r"\\\1", arg) + '"'


def actualizar_autoarranque(ajustes):
    """Crea o borra el lanzador de autoarranque XDG según haya nubes marcadas."""
    if ajustes.get("automontaje"):
        os.makedirs(os.path.dirname(ARCHIVO_AUTOSTART), exist_ok=True)
        exec_line = _linea_exec("--montar-auto")
        with open(ARCHIVO_AUTOSTART, "w", encoding="utf-8") as f:
            f.write(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=Lázaro Nubes (montaje automático)\n"
                "Comment=Monta Google Drive, OneDrive y Dropbox al iniciar sesión\n"
                "Exec=%s\n"
                "Icon=%s\n"
                "Terminal=false\n"
                "NoDisplay=true\n"
                "X-GNOME-Autostart-enabled=true\n"
                "X-GNOME-Autostart-Delay=5\n" % (exec_line, APP_ID)
            )
    elif os.path.exists(ARCHIVO_AUTOSTART):
        os.remove(ARCHIVO_AUTOSTART)


def montar_automaticamente(reintentos=12, pausa=10):
    """Montaje al iniciar sesión: reintenta mientras la red se conecta."""
    ajustes = cargar_ajustes()
    if ajustes.get("equipo_compartido"):
        limpiar_sesion_si_hace_falta()   # cada sesión empieza sin cuentas conectadas
        return 0
    existentes = {n for n, _ in listar_remotos()}
    pendientes = [n for n in ajustes.get("automontaje", []) if n in existentes]
    for intento in range(reintentos):
        if not pendientes:
            break
        siguientes = []
        for nombre in pendientes:
            ok, msg = montar(nombre, ajustes)
            print("[%s] %s: %s" % (intento + 1, nombre, msg.splitlines()[0] if msg else ""))
            if ok:
                anadir_marcador(punto_montaje(nombre, ajustes), nombre)
            else:
                siguientes.append(nombre)
        pendientes = siguientes
        if pendientes:
            time.sleep(pausa)
    return 0 if not pendientes else 1


def procesos_montaje(nombre):
    """PIDs de «rclone mount NOMBRE:» del usuario."""
    pids = []
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            if os.stat("/proc/" + d).st_uid != os.getuid():
                continue
            with open("/proc/%s/cmdline" % d, "rb") as f:
                partes = f.read().split(b"\0")
        except OSError:
            continue
        if (len(partes) > 2 and os.path.basename(partes[0]) == b"rclone"
                and partes[1] == b"mount" and partes[2] == (nombre + ":").encode()):
            pids.append(int(d))
    return pids


def desmontar_a_la_fuerza(nombre, ruta):
    """Desmonta aunque algún programa tenga archivos abiertos: termina el proceso de
    rclone (así su sesión deja de estar en memoria) y suelta la carpeta."""
    desmontar(ruta)
    # Ojo: el desmontaje «perezoso» (-uz) suelta la carpeta aunque un programa tenga un
    # archivo abierto, pero rclone sigue vivo (con la sesión en memoria) hasta que se
    # cierre. Por eso se espera a que termine y, si no, se le cierra.
    for _ in range(50):
        if not procesos_montaje(nombre):
            break
        time.sleep(0.1)
    import signal
    for pid in procesos_montaje(nombre):
        for senal in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.kill(pid, senal)
            except OSError:
                break
            for _ in range(20):
                if pid not in procesos_montaje(nombre):   # también si queda como zombi
                    break
                time.sleep(0.1)
    fm = fusermount_bin()
    if fm and esta_montado(ruta):
        ejecutar([fm, "-uz", ruta], timeout=15)
    return not esta_montado(ruta) and not procesos_montaje(nombre)


def montajes_rclone_en(base):
    """(nombre, carpeta) de los montajes de rclone que hay dentro de `base`."""
    base = os.path.realpath(os.path.expanduser(base))
    encontrados = []
    try:
        with open("/proc/mounts", encoding="utf-8", errors="replace") as f:
            for linea in f:
                partes = linea.split()
                if len(partes) < 3 or not partes[2].startswith("fuse.rclone"):
                    continue
                ruta = _decodificar_mounts(partes[1])
                if ruta == base or ruta.startswith(base + os.sep):
                    # La aplicación monta cada nube en una carpeta con su nombre
                    encontrados.append((os.path.basename(ruta), ruta))
    except OSError:
        pass
    return encontrados


def olvidar_todo():
    """Modo «equipo compartido»: desmonta y olvida todas las cuentas y borra la caché
    de archivos abiertos, para que la siguiente persona no acceda a ellas.
    Devuelve la lista de nubes que NO se pudieron desconectar del todo."""
    ajustes = cargar_ajustes()
    problemas = []
    for nombre, _ in listar_remotos():
        if not desmontar_a_la_fuerza(nombre, punto_montaje(nombre, ajustes)):
            # Se conserva la conexión para poder reintentarlo cuando se cierre el programa
            problemas.append(nombre)
            continue
        quitar_marcador(punto_montaje(nombre, ajustes))
        eliminar_remoto(nombre)
        if any(n == nombre for n, _ in listar_remotos()):
            # La cuenta sigue guardada: se avisa en vez de decir que se olvidó
            problemas.append(nombre)
        if "/" in nombre or nombre in (".", ".."):
            continue                    # no es un nombre de rclone: no se arma ninguna ruta
        for sub in ("vfs", "vfsMeta"):
            cache = os.path.join(XDG_CACHE, "rclone", sub, nombre)
            if os.path.isdir(cache):
                shutil.rmtree(cache, ignore_errors=True)
        # Los registros dicen nombres y carpetas de los archivos de esa nube
        for archivo in (nombre + ".log", nombre + "-sincronizacion.log"):
            try:
                os.unlink(os.path.join(DIR_LOGS, archivo))
            except OSError:
                pass

    # Montajes que siguen ahí aunque su conexión ya no exista (p. ej. borrada desde la
    # terminal): también se desmontan, para que el botón del icono haga lo que promete
    for nombre, ruta in montajes_rclone_en(ajustes["carpeta_base"]):
        if desmontar_a_la_fuerza(nombre, ruta):
            quitar_marcador(ruta)
        elif nombre not in problemas:
            problemas.append(nombre)

    # Los listados de la sincronización (bisync) y el estado del icono tienen la
    # lista de archivos de la persona anterior. Si alguna nube no se pudo olvidar,
    # se conserva su historial de sincronización para no tener que volver a unir.
    if not problemas:
        shutil.rmtree(os.path.join(XDG_CACHE, "rclone", "bisync"), ignore_errors=True)
    try:
        os.unlink(ARCHIVO_ESTADO)
    except OSError:
        pass

    def limpiar(a):
        a["automontaje"] = []
        a["sincronizacion"] = {}
    modificar_ajustes(limpiar)
    actualizar_autoarranque(cargar_ajustes())
    return problemas


def _identidad_sesion():
    """Identifica el inicio de sesión actual. Sin systemd-logind (Alpine con OpenRC,
    startx…) XDG_SESSION_ID suele estar vacío: la dirección del bus D-Bus de la sesión
    (distinta en cada inicio de sesión gráfica) permite distinguir a dos docentes que
    entran uno tras otro sin reiniciar el equipo."""
    import hashlib
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            arranque = f.read().strip()
    except OSError:
        arranque = "?"
    datos = "\0".join((arranque, os.environ.get("XDG_SESSION_ID", ""),
                       os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")))
    return hashlib.sha256(datos.encode()).hexdigest()[:32]


def marcar_sesion_limpia():
    """Marca la sesión actual como ya limpia (al activar el modo compartido a mano)."""
    with open(os.path.join(asegurar_dir(DIR_EJEC), "sesion-limpia"), "w", encoding="utf-8") as f:
        f.write(_identidad_sesion())


def limpiar_sesion_si_hace_falta():
    """Modo «equipo compartido»: olvida las cuentas UNA sola vez por inicio de sesión.
    Si el icono se reinicia a mitad de sesión, no borra lo que el docente acaba de conectar.
    Devuelve None si no hizo nada, o la lista de nubes que no se pudieron desconectar."""
    if not cargar_ajustes().get("equipo_compartido"):
        return None
    import fcntl
    marca = os.path.join(asegurar_dir(DIR_EJEC), "sesion-limpia")
    identidad = _identidad_sesion()
    # Si la ventana y el icono arrancan a la vez, limpia solo uno; el otro espera y
    # después ve la marca de esta sesión y no hace nada
    with open(marca + ".lock", "a") as bloqueo:
        fcntl.flock(bloqueo, fcntl.LOCK_EX)
        try:
            try:
                with open(marca, encoding="utf-8") as f:
                    if f.read().strip() == identidad:
                        return None              # esta sesión ya empezó limpia
            except OSError:
                pass
            problemas = olvidar_todo()
            with open(marca, "w", encoding="utf-8") as f:
                f.write(identidad)
            return problemas
        finally:
            fcntl.flock(bloqueo, fcntl.LOCK_UN)


def desmontar_todo():
    ajustes = cargar_ajustes()
    errores = 0
    for nombre, _ in listar_remotos():
        ruta = punto_montaje(nombre, ajustes)
        if esta_montado(ruta):
            ok, msg = desmontar(ruta)
            print("%s: %s" % (nombre, msg.splitlines()[0]))
            errores += 0 if ok else 1
    return 1 if errores else 0


# ----------------------- Sincronización (rclone bisync) ---------------------
#
# Además de «montar», una nube puede «sincronizarse» con una carpeta local:
# se guarda una copia completa en el disco (funciona sin Internet) y el icono
# del área de notificaciones (nubes_bandeja.py) ejecuta «rclone bisync» cada
# pocos minutos y cuando detecta cambios en la carpeta.

ARCHIVO_ESTADO = os.path.join(DIR_LOGS, "estado.json")
DIR_PETICIONES = os.path.join(DIR_EJEC, "peticiones")
ARCHIVO_BLOQUEO_BANDEJA = os.path.join(DIR_EJEC, "bandeja.lock")
ARCHIVO_AUTOSTART_BANDEJA = os.path.join(XDG_CONFIG, "autostart", APP_ID + "-bandeja.desktop")
CARPETA_SINC_BASE = os.path.join(HOME, "NubesSincronizadas")
INTERVALOS_MIN = [2, 5, 15, 30, 60]

URL_WEB = {
    "drive": "https://drive.google.com/drive/my-drive",
    "onedrive": "https://www.office.com/launch/onedrive",
    "dropbox": "https://www.dropbox.com/home",
}

# Archivos temporales que no se sincronizan ni se avisan como «nuevos»
_IGNORAR = re.compile(r"(^\.~lock\..*#$|\.partial$|^~\$|\.swp$|\.part$|\.crdownload$|^\.goutputstream)")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def version_tupla():
    m = re.search(r"v(\d+)\.(\d+)", version_rclone() or "")
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def carpeta_sinc_defecto(nombre):
    return os.path.join(CARPETA_SINC_BASE, nombre)


def orden_bisync(nombre, tipo, carpeta, resync=False, version=None, bwlimit=None):
    """Construye la orden de rclone bisync entre la carpeta local y la nube."""
    v = version or version_tupla()
    if not rclone_bin():
        raise RuntimeError("rclone no está instalado.")
    orden = [rclone_bin(), "bisync", carpeta, nombre + ":",
             "--create-empty-src-dirs", "-v",
             "--exclude", ".~lock.*#", "--exclude", "*.partial", "--exclude", "~$*"]
    if v >= (1, 66):
        # Modo robusto: se recupera de interrupciones y resuelve conflictos
        # quedándose con la versión más reciente (la otra se renombra).
        orden += ["--resilient", "--recover", "--max-lock", "2m",
                  "--conflict-resolve", "newer", "--color", "NEVER"]
    if tipo == "drive":
        orden += ["--drive-skip-gdocs"]   # los Docs de Google no son archivos reales
    orden += opciones_red(tipo, bwlimit)
    if resync:
        # Primera vez (o reparación): une ambas carpetas SIN borrar nada.
        orden += ["--resync"]
        if v >= (1, 66):
            orden += ["--resync-mode", "newer"]
    return orden


def instantanea(carpeta):
    """Conjunto de rutas relativas de los archivos de una carpeta."""
    archivos = set()
    for raiz, _dirs, nombres in os.walk(carpeta):
        for n in nombres:
            if not _IGNORAR.search(n):
                archivos.add(os.path.relpath(os.path.join(raiz, n), carpeta))
    return archivos


def ignorar_archivo(nombre_archivo):
    return bool(_IGNORAR.search(os.path.basename(nombre_archivo)))


def necesita_resync(salida):
    """True si bisync perdió su historial y hay que volver a unir las carpetas."""
    s = _ANSI.sub("", salida).lower()
    return any(t in s for t in ("cannot find prior", "empty prior path", "must run --resync",
                                "listing file not found"))


def interpretar_error(salida):
    """Convierte la salida de rclone en un mensaje entendible."""
    s = _ANSI.sub("", salida)
    bajo = s.lower()
    casos = [
        (("didn't find section in config",), "La conexión ya no existe en rclone."),
        (("invalid_grant", "token expired", "couldn't fetch token", "unauthorized", "401"),
         "La sesión con el servicio caducó. Abre Lázaro Nubes → «Mis nubes» y pulsa "
         "«Reconectar sesión»."),
        (("too many deletes",),
         "Se detuvo por seguridad: se iban a borrar demasiados archivos de una vez. "
         "Revisa la carpeta; si todo está bien usa «Reparar» (une ambas copias sin borrar nada)."),
        (("no such host", "network is unreachable", "dial tcp", "i/o timeout",
          "connection refused", "temporary failure in name resolution"),
         "Sin conexión a Internet. Se reintentará automáticamente."),
        (("prior lock file found", "lock file found"),
         "Ya hay otra sincronización de esta carpeta en curso."),
        (("no space left",), "No queda espacio libre en el disco de este equipo."),
        (("quota", "insufficient storage", "insufficientstorage"),
         "Tu nube está llena: no queda espacio en la cuenta."),
        (("permission denied",), "Permiso denegado al leer o escribir algún archivo."),
        (("file name too long",),
         "La ruta de la carpeta local es demasiado larga para rclone. Elige una carpeta con una "
         "ruta más corta (por ejemplo ~/NubesSincronizadas/%s)." % "<nombre>"),
    ]
    for claves, mensaje in casos:
        if any(c in bajo for c in claves):
            return mensaje
    errores = [l for l in s.splitlines() if "ERROR" in l or "CRITICAL" in l or "Fatal" in l]
    linea = (errores or s.strip().splitlines() or ["Error desconocido"])[-1]
    return re.sub(r"^\d{4}/\d\d/\d\d \d\d:\d\d:\d\d\s+\w+\s*:\s*", "", linea).strip()[:300]


def leer_estado():
    """Estado publicado por el icono de la bandeja (para mostrarlo en la ventana)."""
    try:
        with open(ARCHIVO_ESTADO, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def escribir_estado(estado):
    asegurar_dir(DIR_LOGS)
    tmp = ARCHIVO_ESTADO + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(estado, f, ensure_ascii=False)
    os.replace(tmp, ARCHIVO_ESTADO)


def pedir_a_bandeja(peticion, nombre=""):
    """Deja una petición (sincronizar, reparar, pausar...) que el icono atiende en segundos."""
    asegurar_dir(DIR_EJEC)
    asegurar_dir(DIR_PETICIONES)
    archivo = peticion + ("--" + nombre if nombre else "")
    with open(os.path.join(DIR_PETICIONES, archivo), "w"):
        pass


ARCHIVO_BLOQUEO_VENTANA = os.path.join(DIR_EJEC, "ventana.lock")
ARCHIVO_MOSTRAR_VENTANA = os.path.join(DIR_EJEC, "mostrar-ventana")
ARCHIVO_CERRAR_VENTANA = os.path.join(DIR_EJEC, "cerrar-ventana")


def bandeja_en_ejecucion():
    return _bloqueado(ARCHIVO_BLOQUEO_BANDEJA)


def ventana_en_ejecucion():
    return _bloqueado(ARCHIVO_BLOQUEO_VENTANA)


def pedir_mostrar_ventana():
    """Pide a la ventana ya abierta que se muestre al frente."""
    asegurar_dir(DIR_EJEC)
    with open(ARCHIVO_MOSTRAR_VENTANA, "w"):
        pass


def pedir_cerrar_ventana():
    """Pide a la ventana abierta que se cierre (segundo clic en el icono)."""
    asegurar_dir(DIR_EJEC)
    with open(ARCHIVO_CERRAR_VENTANA, "w"):
        pass


def _bloqueado(ruta):
    """True si otro proceso tiene tomado el bloqueo `ruta` (programa en ejecución)."""
    import fcntl
    try:
        asegurar_dir(DIR_EJEC)
        with open(ruta, "a") as f:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return True
            fcntl.flock(f, fcntl.LOCK_UN)
            return False
    except OSError:
        return False


def gobject_disponible():
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio  # noqa: F401
        return True
    except (ImportError, ValueError):
        return False


def _linea_exec(argumento):
    lanzador = os.path.join(HOME, ".local", "bin", APP_ID)
    if os.access(lanzador, os.X_OK):
        return _comillas_desktop(lanzador) + " " + argumento
    return " ".join(_comillas_desktop(a) for a in
                    (sys.executable, os.path.abspath(__file__), argumento))


def crear_autoarranque_bandeja():
    os.makedirs(os.path.dirname(ARCHIVO_AUTOSTART_BANDEJA), exist_ok=True)
    with open(ARCHIVO_AUTOSTART_BANDEJA, "w", encoding="utf-8") as f:
        f.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Lázaro Nubes (icono de sincronización)\n"
            "Comment=Icono en el área de notificaciones con el estado de tus nubes\n"
            "Exec=%s\n"
            "Icon=%s\n"
            "Terminal=false\n"
            "NoDisplay=true\n"
            "X-GNOME-Autostart-enabled=true\n"
            "X-GNOME-Autostart-Delay=8\n"
            "X-KDE-autostart-after=panel\n" % (_linea_exec("--bandeja"), APP_ID)
        )


def iniciar_bandeja():
    """Arranca el icono del área de notificaciones si no está en marcha."""
    if bandeja_en_ejecucion():
        return True, "El icono ya está en marcha."
    # Sin PyGObject se inicia igual: sincroniza sin icono (nubes_sinc.py)
    crear_autoarranque_bandeja()
    asegurar_dir(DIR_LOGS)
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nubes_bandeja.py")
    try:
        with open(os.path.join(DIR_LOGS, "bandeja.log"), "a") as log:
            subprocess.Popen([sys.executable, script], stdin=subprocess.DEVNULL, stdout=log,
                             stderr=log, start_new_session=True)
    except OSError as e:
        return False, "No se pudo iniciar el icono: %s" % e
    return True, "Icono iniciado."


def hace(ts):
    """Texto relativo: «hace 3 min»."""
    if not ts:
        return "nunca"
    d = time.time() - ts
    if d < 60:
        return "hace un momento"
    if d < 3600:
        return "hace %d min" % (d // 60)
    if d < 86400:
        return "hace %d h" % (d // 3600)
    return time.strftime("el %d/%m a las %H:%M", time.localtime(ts))


# ==========================================================================
#  INTERFAZ GRÁFICA (Tkinter)
# ==========================================================================

def iniciar_interfaz():
    # Una sola ventana: si ya hay una abierta, se trae al frente y no se abre otra.
    import fcntl
    asegurar_dir(DIR_EJEC)
    bloqueo = open(ARCHIVO_BLOQUEO_VENTANA, "a")
    try:
        fcntl.flock(bloqueo, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        pedir_mostrar_ventana()
        print("Lázaro Nubes ya está abierta: se muestra la ventana existente.")
        return 0
    # Modo «equipo compartido»: limpiar ANTES de mostrar nada, para que nadie vea las
    # cuentas del usuario anterior aunque abra la ventana nada más entrar al escritorio
    problemas_limpieza = limpiar_sesion_si_hace_falta()
    for antigua in (ARCHIVO_MOSTRAR_VENTANA, ARCHIVO_CERRAR_VENTANA):   # peticiones antiguas
        try:
            os.remove(antigua)
        except OSError:
            pass

    try:
        import tkinter as tk
        from tkinter import ttk, messagebox, filedialog
    except ImportError:
        distro, gestor = detectar_distribucion()
        print("ERROR: falta Tkinter (la biblioteca gráfica de Python).\n"
              "Instálala con:\n  " + COMANDOS_INSTALACION.get(gestor, "el paquete python3-tk de tu distribución"),
              file=sys.stderr)
        return 1

    class Ayuda:
        """Muestra un mensaje explicativo al pasar el ratón sobre un elemento."""

        def __init__(self, widget, texto):
            self.widget, self.texto, self.ventana = widget, texto, None
            widget.bind("<Enter>", self.mostrar, add="+")
            widget.bind("<Leave>", self.ocultar, add="+")
            widget.bind("<ButtonPress>", self.ocultar, add="+")

        def mostrar(self, _evento=None):
            if self.ventana:
                return
            x = self.widget.winfo_rootx() + 12
            y = self.widget.winfo_rooty() + self.widget.winfo_height() + 4
            self.ventana = tk.Toplevel(self.widget)
            self.ventana.wm_overrideredirect(True)
            self.ventana.wm_geometry("+%d+%d" % (x, y))
            tk.Label(self.ventana, text=self.texto, justify="left", wraplength=360,
                     background="#ffffe0", foreground="#222", relief="solid",
                     borderwidth=1, padx=6, pady=4).pack()

        def ocultar(self, _evento=None):
            if self.ventana:
                self.ventana.destroy()
                self.ventana = None

    class Aplicacion(tk.Tk):
        def __init__(self):
            super().__init__(className=APP_ID)
            self.title(APP_NOMBRE)
            ancho, alto = self.winfo_screenwidth(), self.winfo_screenheight()
            self.geometry("%dx%d" % (min(980, ancho - 40), min(800, alto - 90)))
            self.minsize(760, 560)
            self.ajustes = cargar_ajustes()
            self.cola = queue.Queue()
            self.proceso_config = None
            self.url_autorizacion = None

            estilo = ttk.Style(self)
            if "clam" in estilo.theme_names():
                estilo.theme_use("clam")
            estilo.configure("Titulo.TLabel", font=("TkDefaultFont", 14, "bold"))
            estilo.configure("Ok.TLabel", foreground="#1a7f37")
            estilo.configure("Mal.TLabel", foreground="#c62828")
            estilo.configure("Acento.TButton", font=("TkDefaultFont", 10, "bold"))

            self.estado = tk.StringVar(value="Listo.")
            ttk.Label(self, textvariable=self.estado, anchor="w", padding=(10, 4),
                      relief="sunken").pack(side="bottom", fill="x")

            self.cuaderno = ttk.Notebook(self)
            self.cuaderno.pack(fill="both", expand=True, padx=8, pady=(8, 4))
            self.pest_req = ttk.Frame(self.cuaderno, padding=12)
            self.pest_con = ttk.Frame(self.cuaderno, padding=12)
            self.pest_mis = ttk.Frame(self.cuaderno, padding=12)
            self.pest_ayu = ttk.Frame(self.cuaderno, padding=12)
            self.cuaderno.add(self.pest_req, text="  1. Requisitos  ")
            self.cuaderno.add(self.pest_con, text="  2. Conectar una nube  ")
            self.cuaderno.add(self.pest_mis, text="  3. Mis nubes  ")
            self.cuaderno.add(self.pest_ayu, text="  Ayuda  ")


            self.construir_requisitos()
            self.construir_conectar()
            self.construir_mis_nubes()
            self.construir_ayuda()

            self.after(100, self.procesar_cola)
            self.after(200, self.comprobar_requisitos)
            self.after(300, self.refrescar_lista)
            self.after(5000, self.refresco_periodico)
            self.after(1500, self.asegurar_icono)
            self.after(400, self.vigilar_peticion_mostrar)
            self.protocol("WM_DELETE_WINDOW", self.al_cerrar)

        def al_cerrar(self):
            """Cerrar la ventana cancela una conexión en curso (si no, quedaría colgada
            ocupando el puerto y bloquearía el siguiente intento)."""
            if self.proceso_config and self.proceso_config.poll() is None:
                if not messagebox.askyesno(APP_NOMBRE, (
                        "Hay una conexión en curso esperando a que inicies sesión en el navegador.\n\n"
                        "Si cierras la ventana se cancelará. ¿Cerrar de todos modos?")):
                    return
                self.proceso_config.terminate()
            self.destroy()

        def vigilar_peticion_mostrar(self):
            """Otra instancia (o el icono) pidió abrir la ventana: traer esta al frente."""
            if os.path.exists(ARCHIVO_MOSTRAR_VENTANA):
                try:
                    os.remove(ARCHIVO_MOSTRAR_VENTANA)
                except OSError:
                    pass
                self.mostrar_al_frente()
            if os.path.exists(ARCHIVO_CERRAR_VENTANA):
                try:
                    os.remove(ARCHIVO_CERRAR_VENTANA)
                except OSError:
                    pass
                if self.proceso_config and self.proceso_config.poll() is None:
                    # Hay un inicio de sesión en curso: cerrar lo interrumpiría.
                    self.mostrar_al_frente()
                    self.estado.set("Termina de conectar la cuenta antes de cerrar la ventana.")
                else:
                    self.destroy()
                    return
            self.after(400, self.vigilar_peticion_mostrar)

        def mostrar_al_frente(self):
            self.deiconify()
            self.lift()
            self.attributes("-topmost", True)
            self.after(300, lambda: self.attributes("-topmost", False))
            self.focus_force()
            self.refrescar_lista()

        def asegurar_icono(self):
            """El icono de la bandeja muestra el estado y hace las sincronizaciones."""
            if rclone_bin():
                iniciar_bandeja()

        def modificar_ajustes(self, funcion):
            """Relee los ajustes del disco, aplica el cambio y guarda bajo un bloqueo
            compartido con el icono de la bandeja, para no pisarse los cambios."""
            self.ajustes = modificar_ajustes(funcion)

        def validar_carpeta_sinc(self, ruta, nombre):
            """Devuelve un mensaje de error si la carpeta no sirve para sincronizar."""
            ruta = os.path.realpath(ruta)
            prohibidas = {"/", os.path.realpath(HOME)}
            if ruta in prohibidas or ruta.startswith(("/proc", "/sys", "/dev", "/usr", "/etc", "/bin")):
                return "No se puede sincronizar «%s». Elige una subcarpeta propia, por ejemplo %s" % (
                    ruta, carpeta_sinc_defecto(nombre))
            base = os.path.realpath(os.path.expanduser(self.ajustes["carpeta_base"]))
            if ruta == base or ruta.startswith(base + os.sep):
                return ("Esa carpeta está dentro de la carpeta de montaje (%s). Una carpeta "
                        "sincronizada debe estar fuera de ella." % base)
            for otro, conf in self.ajustes.get("sincronizacion", {}).items():
                if otro == nombre:
                    continue
                o = os.path.realpath(os.path.expanduser(conf.get("carpeta", "")))
                if ruta == o or ruta.startswith(o + os.sep) or o.startswith(ruta + os.sep):
                    return "Esa carpeta coincide con la sincronización de «%s». Usa otra." % otro
            return None

        # ----------------------- utilidades de hilos -----------------------
        def en_segundo_plano(self, funcion, al_terminar=None, *args):
            def trabajo():
                try:
                    resultado = funcion(*args)
                except Exception as e:  # noqa: BLE001 - se muestra al usuario
                    resultado = e
                if al_terminar:
                    self.cola.put((al_terminar, resultado))
            threading.Thread(target=trabajo, daemon=True).start()

        def procesar_cola(self):
            try:
                while True:
                    funcion, dato = self.cola.get_nowait()
                    funcion(dato)
            except queue.Empty:
                pass
            self.after(100, self.procesar_cola)

        # =========================== PESTAÑA 1 ===========================
        def construir_requisitos(self):
            p = self._desplazable(self.pest_req)
            ttk.Label(p, text="Bienvenido a " + APP_NOMBRE, style="Titulo.TLabel").pack(anchor="w")
            self._texto_ajustable(p, (
                "Esta aplicación te ayuda a usar rclone para conectar tus cuentas de "
                "Google Drive, OneDrive y Dropbox. Puedes «montar» cada nube como una carpeta "
                "(en ~/Nubes) o «sincronizarla» con una carpeta local que funciona sin Internet. "
                "Ambas aparecen en la barra lateral de tu explorador de archivos y un icono en el "
                "área de notificaciones te informa de su estado.\n\n"
                "Antes de empezar, comprobamos que tu sistema tiene todo lo necesario:"
            )).pack(anchor="w", fill="x", pady=(6, 10))

            self.marco_checks = ttk.Frame(p)
            self.marco_checks.pack(fill="x")
            self.marco_checks.columnconfigure(2, weight=1)
            self.detalles_req = []

            def ajustar_detalles(evento):
                # La columna de detalles usa el ancho que dejan el icono y el nombre
                ancho = max(200, evento.width - 290)
                for etiqueta in self.detalles_req:
                    if etiqueta.winfo_exists():
                        etiqueta.configure(wraplength=ancho)
            self.marco_checks.bind("<Configure>", ajustar_detalles)

            self.marco_instalar = ttk.LabelFrame(p, text=" Cómo instalar lo que falta ", padding=10)
            self.texto_instalar = tk.Text(self.marco_instalar, height=3, wrap="word",
                                          font=("TkFixedFont", 10))
            self.texto_instalar.pack(fill="x")
            fila = ttk.Frame(self.marco_instalar)
            fila.pack(fill="x", pady=(6, 0))
            ttk.Button(fila, text="Copiar orden", command=self.copiar_orden_instalar).pack(side="left")
            ttk.Label(fila, text="Pégala en una terminal, escribe tu contraseña y vuelve a comprobar.",
                      wraplength=600).pack(side="left", padx=8, fill="x", expand=True)
            fila.winfo_children()[-1].bind(
                "<Configure>", lambda e: e.widget.configure(wraplength=max(200, e.width - 10)))

            fila2 = ttk.Frame(p)
            fila2.pack(fill="x", pady=12, side="bottom")
            ttk.Button(fila2, text="Volver a comprobar", command=self.comprobar_requisitos).pack(side="left")
            self.boton_siguiente = ttk.Button(fila2, text="Siguiente: conectar una nube →",
                                              style="Acento.TButton",
                                              command=lambda: self.cuaderno.select(self.pest_con))
            self.boton_siguiente.pack(side="right")

        def comprobar_requisitos(self):
            for w in self.marco_checks.winfo_children():
                w.destroy()
            self.detalles_req.clear()
            distro, gestor = detectar_distribucion()
            ver = version_rclone()
            fm = fusermount_bin()
            exploradores = detectar_exploradores()
            checks = [
                ("Sistema detectado", True, "%s (gestor de paquetes: %s)" % (distro, gestor or "desconocido"),
                 "Usamos esto para decirte cómo instalar lo que falte."),
                ("rclone", bool(ver), ver or "No instalado",
                 "rclone es el programa que realmente habla con Google, Microsoft y Dropbox. "
                 "Esta aplicación es solo una interfaz amigable para él."),
                ("FUSE (fusermount3)", bool(fm), fm or "No instalado",
                 "FUSE permite que una nube aparezca como una carpeta normal. Sin FUSE se "
                 "pueden configurar las cuentas pero no montarlas."),
                ("Dispositivo /dev/fuse", os.path.exists("/dev/fuse"),
                 "Disponible" if os.path.exists("/dev/fuse") else "No disponible: ejecuta «sudo modprobe fuse»",
                 "Es el módulo del núcleo Linux que usa FUSE. En Alpine añade «fuse» a "
                 "/etc/modules para cargarlo al arrancar."),
                ("Abrir enlaces (xdg-open)", bool(shutil.which("xdg-open")),
                 shutil.which("xdg-open") or "No instalado (se intentará con otros métodos)",
                 "Sirve para abrir el navegador al iniciar sesión y abrir carpetas en tu explorador."),
                ("Icono de notificaciones (PyGObject)", gobject_disponible(),
                 ("Disponible" + (" — en marcha" if bandeja_en_ejecucion() else ""))
                 if gobject_disponible() else "No instalado: sin icono (la sincronización funciona igual)",
                 "PyGObject permite mostrar el icono en el área de notificaciones, avisarte de "
                 "archivos nuevos y sincronizar carpetas automáticamente. En GNOME necesitas "
                 "además la extensión «AppIndicator and KStatusNotifierItem Support»."),
                ("Explorador de archivos", bool(exploradores),
                 ", ".join(n for _, n in exploradores) or "Ninguno conocido detectado",
                 "Las nubes montadas se añaden a la barra lateral de tu explorador."),
            ]
            todo_ok = True
            for fila, (nombre, ok, detalle, ayuda) in enumerate(checks):
                icono = ttk.Label(self.marco_checks, text="✔" if ok else "✘",
                                  style="Ok.TLabel" if ok else "Mal.TLabel",
                                  font=("TkDefaultFont", 13, "bold"))
                icono.grid(row=fila, column=0, sticky="w", padx=(0, 8), pady=3)
                etiqueta = ttk.Label(self.marco_checks, text=nombre, font=("TkDefaultFont", 10, "bold"))
                etiqueta.grid(row=fila, column=1, sticky="w", pady=3)
                detalle_etq = ttk.Label(self.marco_checks, text=detalle,
                                        wraplength=max(200, self.marco_checks.winfo_width() - 290)
                                        if self.marco_checks.winfo_width() > 1 else 560)
                self.detalles_req.append(detalle_etq)
                detalle_etq.grid(
                    row=fila, column=2, sticky="w", padx=12, pady=3)
                Ayuda(etiqueta, ayuda)
                Ayuda(icono, ayuda)
                if nombre in ("rclone", "FUSE (fusermount3)", "Dispositivo /dev/fuse") and not ok:
                    todo_ok = False

            if todo_ok:
                self.marco_instalar.pack_forget()
                self.estado.set("Todo listo. Ve a «2. Conectar una nube».")
            else:
                orden = COMANDOS_INSTALACION.get(gestor) or (
                    "Instala rclone, fuse3 y python3-tk con el gestor de paquetes de tu "
                    "distribución, o descarga rclone desde https://rclone.org/downloads/")
                self.texto_instalar.delete("1.0", "end")
                self.texto_instalar.insert("1.0", orden)
                self.marco_instalar.pack(fill="x", pady=12)
                self.estado.set("Faltan componentes. Mira las instrucciones de instalación.")
            self.boton_siguiente.state(["!disabled"] if ver else ["disabled"])

        def copiar_orden_instalar(self):
            self.clipboard_clear()
            self.clipboard_append(self.texto_instalar.get("1.0", "end").strip())
            self.estado.set("Orden copiada al portapapeles.")

        # =========================== PESTAÑA 2 ===========================
        def _texto_ajustable(self, padre, texto):
            """Etiqueta cuyo texto se reparte en líneas según el ancho disponible."""
            etiqueta = ttk.Label(padre, text=texto, justify="left", wraplength=700)
            etiqueta.bind("<Configure>", lambda e: etiqueta.configure(wraplength=max(300, e.width - 10)))
            return etiqueta

        def _desplazable(self, contenedor):
            """Marco con barra de desplazamiento vertical que solo aparece si el contenido
            no cabe (portátiles de 1366×768 con la barra de tareas visible)."""
            fondo = ttk.Style(self).lookup("TFrame", "background") or None
            lienzo = tk.Canvas(contenedor, highlightthickness=0, borderwidth=0, background=fondo)
            barra = ttk.Scrollbar(contenedor, orient="vertical", command=lienzo.yview)
            interior = ttk.Frame(lienzo)
            ventana = lienzo.create_window((0, 0), window=interior, anchor="nw")
            lienzo.configure(yscrollcommand=barra.set)

            def ajustar(_evento=None):
                necesario = interior.winfo_reqheight()
                visible = lienzo.winfo_height()
                lienzo.itemconfigure(ventana, width=lienzo.winfo_width(),
                                     height=max(necesario, visible))
                lienzo.configure(scrollregion=(0, 0, lienzo.winfo_width(), max(necesario, visible)))
                if necesario > visible + 2:
                    if not barra.winfo_ismapped():
                        barra.pack(side="right", fill="y", before=lienzo)
                elif barra.winfo_ismapped():
                    barra.pack_forget()
                    lienzo.yview_moveto(0)
            interior.bind("<Configure>", ajustar)
            lienzo.bind("<Configure>", ajustar)
            lienzo.pack(side="left", fill="both", expand=True)

            def rueda(evento):
                if not barra.winfo_ismapped() or not str(evento.widget).startswith(str(lienzo)):
                    return
                if isinstance(evento.widget, tk.Text):
                    return                      # el registro tiene su propio desplazamiento
                paso = -1 if (getattr(evento, "num", 0) == 4 or getattr(evento, "delta", 0) > 0) else 1
                lienzo.yview_scroll(paso * 3, "units")
            for secuencia in ("<Button-4>", "<Button-5>", "<MouseWheel>"):
                self.bind_all(secuencia, rueda, add="+")
            return interior

        def construir_conectar(self):
            p = self._desplazable(self.pest_con)
            p.columnconfigure(1, weight=1)
            p.rowconfigure(1, weight=1, minsize=120)

            izq = ttk.LabelFrame(p, text=" Paso 1: elige el servicio ", padding=10)
            izq.grid(row=0, column=0, sticky="nsw", padx=(0, 10))
            self.tipo = tk.StringVar(value="drive")
            for clave, info in PROVEEDORES.items():
                ttk.Radiobutton(izq, text=info["titulo"], value=clave, variable=self.tipo,
                                command=self.cambiar_proveedor).pack(anchor="w", pady=4)

            der = ttk.LabelFrame(p, text=" Paso 2: revisa las opciones ", padding=10)
            der.grid(row=0, column=1, sticky="nsew")
            der.columnconfigure(1, weight=1)

            def ajustar_textos(evento):
                # Los textos largos se reparten según el ancho real del panel
                ancho = max(300, evento.width - 30)
                self.desc.configure(wraplength=ancho)
                if hasattr(self, "texto_scope"):
                    self.texto_scope.configure(wraplength=ancho)
                if hasattr(self, "texto_avanzado"):
                    self.texto_avanzado.configure(wraplength=ancho)
            der.bind("<Configure>", ajustar_textos)
            self.desc = ttk.Label(der, wraplength=640, justify="left")
            self.desc.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))

            ttk.Label(der, text="Nombre de la conexión:").grid(row=1, column=0, sticky="w")
            self.nombre = tk.StringVar()
            e = ttk.Entry(der, textvariable=self.nombre, width=28)
            e.grid(row=1, column=1, sticky="w", padx=6)
            Ayuda(e, "Un nombre corto para reconocer esta cuenta, por ejemplo «DriveTrabajo». "
                     "Será también el nombre de la carpeta. Usa letras, números, guiones o puntos, "
                     "sin espacios.")

            self.fila_scope = ttk.Frame(der)
            self.fila_scope.grid(row=2, column=0, columnspan=3, sticky="w", pady=4)
            ttk.Label(self.fila_scope, text="Permisos:").grid(row=0, column=0, sticky="w")
            self.scope = tk.StringVar()
            self.combo_scope = ttk.Combobox(self.fila_scope, textvariable=self.scope, state="readonly",
                                            width=42)
            self.combo_scope.grid(row=0, column=1, sticky="w", padx=6)
            self.combo_scope.bind("<<ComboboxSelected>>", lambda e: self.explicar_permisos())
            self.texto_scope = ttk.Label(self.fila_scope, wraplength=600, justify="left",
                                         foreground="#555")
            self.texto_scope.grid(row=1, column=0, columnspan=2, sticky="w")
            Ayuda(self.combo_scope, "Qué puede hacer rclone con tu cuenta. Si tu institución (colegio, "
                                    "universidad, empresa) bloquea la conexión pidiendo la aprobación de "
                                    "un administrador, elige los permisos «Mínimos».")

            self.modo = tk.StringVar(value="montar")
            fila_modo = ttk.Frame(der)
            fila_modo.grid(row=3, column=0, columnspan=3, sticky="w", pady=(6, 2))
            ttk.Label(fila_modo, text="Cómo usarla:").pack(side="left")
            r1 = ttk.Radiobutton(fila_modo, text="Montar como carpeta", value="montar",
                                 variable=self.modo, command=self.cambiar_modo)
            r1.pack(side="left", padx=6)
            r2 = ttk.Radiobutton(fila_modo, text="Sincronizar con una carpeta local", value="sincronizar",
                                 variable=self.modo, command=self.cambiar_modo)
            r2.pack(side="left")
            Ayuda(r1, "MONTAR: la nube aparece como una carpeta, pero los archivos se descargan "
                      "solo cuando los abres. No ocupa espacio en el disco, pero necesita Internet.")
            Ayuda(r2, "SINCRONIZAR: se guarda una copia completa en una carpeta de tu equipo que "
                      "funciona sin Internet. El icono del área de notificaciones sube y baja los "
                      "cambios automáticamente. Ocupa en tu disco lo mismo que tu nube.")

            self.marco_montar = ttk.Frame(der)
            self.montar_ahora = tk.BooleanVar(value=True)
            self.auto_inicio = tk.BooleanVar(value=True)
            c1 = ttk.Checkbutton(self.marco_montar, text="Montar ahora y añadir al explorador de archivos",
                                 variable=self.montar_ahora)
            c1.pack(anchor="w")
            Ayuda(c1, "Al terminar, la nube aparecerá como carpeta en ~/Nubes y en la barra "
                      "lateral de tu explorador de archivos.")
            c2 = ttk.Checkbutton(self.marco_montar, text="Montar automáticamente al iniciar sesión",
                                 variable=self.auto_inicio)
            c2.pack(anchor="w")
            self.check_auto = c2

            self.marco_sinc = ttk.Frame(der)
            ttk.Label(self.marco_sinc, text="Carpeta local:").grid(row=0, column=0, sticky="w")
            self.carpeta_sinc = tk.StringVar()
            self.carpeta_sinc_auto = True
            ec = ttk.Entry(self.marco_sinc, textvariable=self.carpeta_sinc, width=42)
            ec.grid(row=0, column=1, sticky="w", padx=6)
            ec.bind("<Key>", lambda e: setattr(self, "carpeta_sinc_auto", False))
            ttk.Button(self.marco_sinc, text="Elegir…", command=self.elegir_carpeta_sinc).grid(row=0, column=2)
            Ayuda(ec, "Aquí se guardará la copia de tu nube. Si la carpeta ya tiene archivos, se "
                      "combinarán con los de la nube sin borrar nada.")
            ttk.Label(self.marco_sinc, text="Sincronizar cada:").grid(row=1, column=0, sticky="w", pady=2)
            self.intervalo_sinc = tk.StringVar(value="5 minutos")
            ci = ttk.Combobox(self.marco_sinc, textvariable=self.intervalo_sinc, state="readonly", width=12,
                              values=["%d minutos" % m for m in INTERVALOS_MIN])
            ci.grid(row=1, column=1, sticky="w", padx=6, pady=2)
            Ayuda(ci, "Cada cuánto se buscan cambios en la nube. Lo que cambies en la carpeta local "
                      "se sube unos segundos después, sin esperar a este intervalo.")
            self.nombre.trace_add("write", self._nombre_cambiado)
            Ayuda(c2, "Crea un lanzador en ~/.config/autostart para que la nube esté disponible "
                      "cada vez que entres a tu escritorio (funciona en GNOME, KDE, XFCE, MATE, "
                      "Cinnamon, LXQt y otros escritorios compatibles con XDG).")

            self.avanzado_visible = tk.BooleanVar(value=False)
            ttk.Checkbutton(der, text="Mostrar opciones avanzadas", variable=self.avanzado_visible,
                            command=self.alternar_avanzado).grid(row=5, column=0, columnspan=3,
                                                                 sticky="w", pady=(8, 0))
            self.marco_avanzado = ttk.Frame(der)
            ttk.Label(self.marco_avanzado, text="ID de cliente (client_id):").grid(row=0, column=0, sticky="w")
            ttk.Label(self.marco_avanzado, text="Secreto (client_secret):").grid(row=1, column=0, sticky="w")
            self.client_id = tk.StringVar()
            self.client_secret = tk.StringVar()
            e1 = ttk.Entry(self.marco_avanzado, textvariable=self.client_id, width=34)
            e2 = ttk.Entry(self.marco_avanzado, textvariable=self.client_secret, width=34, show="•")
            self.marco_avanzado.columnconfigure(1, weight=1)
            e1.grid(row=0, column=1, padx=6, pady=2, sticky="ew")
            e2.grid(row=1, column=1, padx=6, pady=2, sticky="ew")
            self.texto_avanzado = ttk.Label(self.marco_avanzado, wraplength=540, justify="left", text=(
                "Opcional. Déjalo vacío si no sabes qué es. Tener tu propio ID de cliente "
                "(creado en la consola de Google Cloud, Azure o Dropbox) evita los límites de "
                "velocidad compartidos. Guía: https://rclone.org/drive/#making-your-own-client-id"
            ))
            self.texto_avanzado.grid(row=2, column=0, columnspan=2, sticky="w", pady=(4, 0))

            fila_bot = ttk.Frame(der)
            fila_bot.grid(row=7, column=0, columnspan=3, sticky="w", pady=(12, 0))
            self.boton_conectar = ttk.Button(fila_bot, text="Paso 3: Conectar", style="Acento.TButton",
                                             command=self.conectar)
            self.boton_conectar.pack(side="left")
            self.boton_cancelar = ttk.Button(fila_bot, text="Cancelar", command=self.cancelar_conexion,
                                             state="disabled")
            self.boton_cancelar.pack(side="left", padx=6)
            self.boton_url = ttk.Button(fila_bot, text="Abrir / copiar enlace de inicio de sesión",
                                        command=self.abrir_url, state="disabled")
            self.boton_url.pack(side="left")
            Ayuda(self.boton_url, "Si el navegador no se abrió solo, pulsa aquí: intenta abrirlo y "
                                  "además copia el enlace para que lo pegues en tu navegador. "
                                  "Solo funciona en este mismo equipo.")

            registro = ttk.LabelFrame(p, text=" Progreso ", padding=6)
            registro.grid(row=1, column=0, columnspan=2, sticky="nsew", pady=(10, 0))
            self.log = tk.Text(registro, height=5, wrap="word", state="disabled",
                               font=("TkFixedFont", 9), background="white", foreground="#222")
            barra = ttk.Scrollbar(registro, command=self.log.yview)
            self.log.configure(yscrollcommand=barra.set)
            self.log.pack(side="left", fill="both", expand=True)
            barra.pack(side="right", fill="y")

            self.cambiar_proveedor()
            self.cambiar_modo()
            self.aplicar_modo_compartido()

        def aplicar_modo_compartido(self):
            """En modo «equipo compartido» las nubes se olvidan al iniciar cada sesión:
            no tiene sentido ofrecer el montaje automático."""
            if self.ajustes.get("equipo_compartido"):
                self.auto_inicio.set(False)
                self.check_auto.state(["disabled"])
                self.check_auto.configure(text="Montar al iniciar sesión (no en equipo compartido)")
            else:
                self.check_auto.state(["!disabled"])
                self.check_auto.configure(text="Montar automáticamente al iniciar sesión")

        def cambiar_modo(self):
            if self.modo.get() == "sincronizar":
                self.marco_montar.grid_remove()
                self.marco_sinc.grid(row=4, column=0, columnspan=3, sticky="w")
            else:
                self.marco_sinc.grid_remove()
                self.marco_montar.grid(row=4, column=0, columnspan=3, sticky="w")

        def _nombre_cambiado(self, *_):
            if self.carpeta_sinc_auto:
                self.carpeta_sinc.set(carpeta_sinc_defecto(self.nombre.get().strip() or "Nube"))

        def elegir_carpeta_sinc(self):
            elegida = filedialog.askdirectory(initialdir=HOME, title="Carpeta local para sincronizar")
            if elegida:
                self.carpeta_sinc_auto = False
                self.carpeta_sinc.set(elegida)

        def alternar_avanzado(self):
            if self.avanzado_visible.get():
                self.marco_avanzado.grid(row=6, column=0, columnspan=3, sticky="ew", pady=4)
            else:
                self.marco_avanzado.grid_forget()

        def cambiar_proveedor(self):
            info = PROVEEDORES[self.tipo.get()]
            self.desc.configure(text=info["descripcion"])
            sugeridos = {v["nombre_sugerido"] for v in PROVEEDORES.values()}
            actual = self.nombre.get()
            if not actual or actual in sugeridos or actual == getattr(self, "nombre_auto", None):
                existentes = {n for n, _ in listar_remotos()}
                nombre, i = info["nombre_sugerido"], 2
                while nombre in existentes:
                    nombre = "%s%d" % (info["nombre_sugerido"], i)
                    i += 1
                self.nombre_auto = nombre
                self.nombre.set(nombre)
            opciones = PERMISOS.get(self.tipo.get())
            if opciones:
                self.combo_scope.configure(values=[o[0] for o in opciones])
                self.scope.set(opciones[PERMISO_DEFECTO.get(self.tipo.get(), 0)][0])
                self.explicar_permisos()
                self.fila_scope.grid()
            else:
                self.fila_scope.grid_remove()

        def permiso_elegido(self):
            for etiqueta, params, texto in PERMISOS.get(self.tipo.get(), []):
                if etiqueta == self.scope.get():
                    return params, texto
            return [], ""

        def explicar_permisos(self):
            self.texto_scope.configure(text=self.permiso_elegido()[1])

        def escribir_log(self, texto):
            self.log.configure(state="normal")
            self.log.insert("end", texto.rstrip("\n") + "\n")
            self.log.see("end")
            self.log.configure(state="disabled")

        def conectar(self):
            if not rclone_bin():
                messagebox.showerror(APP_NOMBRE, "rclone no está instalado. Revisa la pestaña «Requisitos».")
                return
            nombre = self.nombre.get().strip()
            if not nombre_valido(nombre):
                messagebox.showerror(APP_NOMBRE, "El nombre «%s» no es válido.\n\nUsa solo letras, "
                                     "números, guiones (-), guiones bajos (_) o puntos, sin espacios, "
                                     "y empieza por una letra o número." % nombre)
                return
            if nombre in {n for n, _ in listar_remotos()}:
                messagebox.showerror(APP_NOMBRE, "Ya existe una conexión llamada «%s». Elige otro "
                                     "nombre o elimínala en «Mis nubes»." % nombre)
                return
            if self.modo.get() == "sincronizar":
                if self.ajustes.get("equipo_compartido"):
                    messagebox.showerror(APP_NOMBRE, MSG_COMPARTIDO_SIN_SINC)
                    return
                if any("readonly" in p or ("access_scopes=" in p and "ReadWrite" not in p)
                       for p in self.permiso_elegido()[0]):
                    messagebox.showerror(APP_NOMBRE, MSG_SOLO_LECTURA_SIN_SINC)
                    return
                error = self.validar_carpeta_sinc(os.path.expanduser(self.carpeta_sinc.get().strip()), nombre)
                if error:
                    messagebox.showerror(APP_NOMBRE, error)
                    return
            if not self.puerto_listo():
                return
            tipo = self.tipo.get()
            titulo = PROVEEDORES[tipo]["titulo"]
            if not messagebox.askokcancel(APP_NOMBRE, (
                    "Vamos a conectar %s.\n\n"
                    "1. Se abrirá tu navegador web.\n"
                    "2. Inicia sesión con tu cuenta y acepta los permisos.\n"
                    "3. Cuando el navegador diga «Success!» o «¡Listo!», vuelve a esta ventana.\n\n"
                    "Tus contraseñas nunca pasan por esta aplicación: el inicio de sesión se hace "
                    "directamente en la web de %s." % (titulo, titulo.split()[-1]))):
                return

            params = list(self.permiso_elegido()[0])
            if self.client_id.get().strip():
                params.append("client_id=" + self.client_id.get().strip())
            # El secreto NO va en la línea de órdenes (cualquier usuario del equipo podría
            # leerlo en /proc mientras se inicia sesión): va en el entorno del proceso y,
            # al terminar, se guarda en la configuración de rclone.
            entorno = dict(os.environ)
            self.secreto_pendiente = self.client_secret.get().strip()
            if self.secreto_pendiente:
                entorno["RCLONE_%s_CLIENT_SECRET" % tipo.upper()] = self.secreto_pendiente

            orden = [rclone_bin(), "config", "create", nombre, tipo] + params
            self.log.configure(state="normal")
            self.log.delete("1.0", "end")
            self.log.configure(state="disabled")
            self.escribir_log("Conectando %s como «%s»…" % (titulo, nombre))
            self.escribir_log("Esperando a que inicies sesión en el navegador "
                              "(tienes unos 5 minutos)…")
            self.escribir_log("Si cierras el navegador sin terminar, pulsa «Cancelar» y vuelve a "
                              "intentarlo.\n")
            self.boton_conectar.state(["disabled"])
            self.boton_cancelar.state(["!disabled"])
            self.boton_url.state(["disabled"])
            self.url_autorizacion = None
            self.estado.set("Esperando la autorización en el navegador…")

            def trabajo():
                try:
                    self.proceso_config = subprocess.Popen(
                        orden, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, bufsize=1, env=entorno)
                except OSError as e:
                    self.cola.put((self.escribir_log, "Error: %s" % e))
                    self.cola.put((self.fin_conexion, (nombre, 1)))
                    return
                for linea in self.proceso_config.stdout:
                    self.cola.put((self.linea_rclone, linea))
                codigo = self.proceso_config.wait()
                self.cola.put((self.fin_conexion, (nombre, codigo)))
            threading.Thread(target=trabajo, daemon=True).start()

        def linea_rclone(self, linea):
            m = re.search(r"(http://127\.0\.0\.1:53682/auth\?state=\S+)", linea)
            if m:
                self.url_autorizacion = m.group(1)
                self.boton_url.state(["!disabled"])
                self.escribir_log("→ Si el navegador no se abrió, pulsa «Abrir / copiar enlace de inicio "
                                  "de sesión».")
                return
            # Traducción de los mensajes más habituales de rclone
            if "Waiting for code" in linea:
                self.escribir_log("→ Esperando a que completes el inicio de sesión…")
            elif "Got code" in linea:
                self.escribir_log("✔ Autorización recibida. Guardando la configuración…")
            elif "address already in use" in linea:
                self.escribir_log("✘ El puerto %d está ocupado por otro intento de conexión. Pulsa "
                                  "«Paso 3: Conectar» de nuevo: te ofreceré cancelarlo." % PUERTO_OAUTH)
            elif any(t in linea for t in ("Usage:", "rclone config create name", "--help",
                                          "Use \"rclone", "Flags:")) or linea.startswith("      --"):
                pass                                   # ayuda de rclone: no aporta nada aquí
            elif linea.strip() and not linea.startswith(("[", "type =", "token =", "scope =",
                                                         "drive_id", "drive_type", "client_",
                                                         "access_scopes")):
                # Nunca mostrar credenciales: solo se ocultan líneas que las contienen.
                if not re.search(r'access_token|refresh_token|"token"|token\s*=\s*\{', linea):
                    self.escribir_log(linea)

        def abrir_url(self):
            """Abre el enlace de inicio de sesión y además lo copia, por si el navegador no se abre."""
            if not self.url_autorizacion:
                return
            self.clipboard_clear()
            self.clipboard_append(self.url_autorizacion)
            abrir_url(self.url_autorizacion)
            self.escribir_log("→ Enlace copiado al portapapeles. Si el navegador no se abre, abre "
                              "tu navegador y pégalo (Ctrl+V) en la barra de direcciones:\n   " +
                              self.url_autorizacion)

        def cancelar_conexion(self):
            if self.proceso_config and self.proceso_config.poll() is None:
                self.proceso_config.terminate()
                self.escribir_log("Cancelado por el usuario.")

        def fin_conexion(self, datos):
            nombre, codigo = datos
            self.boton_conectar.state(["!disabled"])
            self.boton_cancelar.state(["disabled"])
            self.boton_url.state(["disabled"])
            self.proceso_config = None
            existe = nombre in {n for n, _ in listar_remotos()}
            if codigo != 0 or not existe:
                if existe:  # quedó a medias: limpiar
                    eliminar_remoto(nombre)
                self.estado.set("La conexión no se completó.")
                self.escribir_log("\n✘ No se completó la conexión (código %s)." % codigo)
                messagebox.showerror(APP_NOMBRE, (
                    "No se pudo completar la conexión.\n\nCausas habituales:\n"
                    "• Cerraste el navegador o no aceptaste los permisos.\n"
                    "• Pasaron más de 5 minutos.\n"
                    "• Quedó colgado un intento anterior: vuelve a pulsar «Conectar» y acepta cancelarlo.\n"
                    "• Sin conexión a Internet.\n"
                    "• Cuenta institucional (colegio, universidad, empresa): Microsoft o Google pidió "
                    "la aprobación de un administrador. Elige «Permisos: Mínimos» e inténtalo de "
                    "nuevo; si aun así la pide, consulta «Cuentas institucionales» en la Ayuda.\n\n"
                    "Revisa el registro de progreso e inténtalo de nuevo."))
                return
            if getattr(self, "secreto_pendiente", ""):
                secreto, self.secreto_pendiente = self.secreto_pendiente, ""

                def guardar():
                    return guardar_secreto(nombre, secreto)

                def guardado(res):
                    if isinstance(res, Exception) or res[0] != 0:
                        self.escribir_log("⚠ No se pudo guardar el secreto (client_secret). La "
                                          "conexión puede fallar al renovar la sesión.")
                        messagebox.showwarning(APP_NOMBRE, (
                            "La cuenta se conectó, pero no se pudo guardar tu «client_secret» en "
                            "la configuración de rclone. Elimina la conexión y vuelve a crearla."))
                    # Montar o sincronizar solo cuando el secreto ya está en rclone.conf
                    self._tras_conectar(nombre)
                self.en_segundo_plano(guardar, guardado)
                return
            self._tras_conectar(nombre)

        def _tras_conectar(self, nombre):
            self.escribir_log("\n✔ ¡«%s» conectada correctamente!" % nombre)
            if self.modo.get() == "sincronizar":
                self.activar_sincronizacion(nombre, self.carpeta_sinc.get(),
                                            int(self.intervalo_sinc.get().split()[0]), desde_conectar=True)
                return
            if self.auto_inicio.get():
                self.modificar_ajustes(lambda a: a["automontaje"].append(nombre)
                                       if nombre not in a["automontaje"] else None)
                actualizar_autoarranque(self.ajustes)
                self.escribir_log("✔ Se montará automáticamente al iniciar sesión.")
            self.refrescar_lista()
            if self.montar_ahora.get():
                self.escribir_log("Montando la carpeta…")
                self.accion_montar(nombre, abrir=True)
            else:
                self.cuaderno.select(self.pest_mis)

        # =========================== PESTAÑA 3 ===========================
        def construir_mis_nubes(self):
            p = self.pest_mis
            self._texto_ajustable(p, (
                "Estas son tus nubes conectadas. «Montar» hace que aparezcan como una carpeta "
                "(los archivos se descargan al abrirlos). «Sincronizar» guarda una copia completa en "
                "una carpeta local que funciona sin Internet; el icono de nube del área de "
                "notificaciones se encarga de mantenerla al día. Pasa el ratón sobre los botones "
                "para ver qué hace cada uno."
            )).pack(anchor="w", fill="x", pady=(0, 8))

            fila_base = ttk.Frame(p)
            fila_base.pack(fill="x", pady=(0, 8))
            ttk.Label(fila_base, text="Carpeta donde se montan las nubes:").pack(side="left")
            self.base = tk.StringVar(value=self.ajustes["carpeta_base"])
            ttk.Entry(fila_base, textvariable=self.base, state="readonly", width=26).pack(side="left", padx=6)
            b = ttk.Button(fila_base, text="Cambiar…", command=self.cambiar_base)
            b.pack(side="left")
            Ayuda(b, "Elige otra carpeta base. Solo se puede cambiar con todas las nubes desmontadas.")

            columnas = ("servicio", "modo", "estado", "carpeta", "auto")
            self.tabla = ttk.Treeview(p, columns=columnas, height=8, selectmode="browse")
            self.tabla.heading("#0", text="Nombre")
            self.tabla.heading("servicio", text="Servicio")
            self.tabla.heading("modo", text="Modo")
            self.tabla.heading("estado", text="Estado")
            self.tabla.heading("carpeta", text="Carpeta")
            self.tabla.heading("auto", text="Al iniciar sesión")
            self.tabla.column("#0", width=120)
            self.tabla.column("servicio", width=130)
            self.tabla.column("modo", width=110)
            self.tabla.column("estado", width=185)
            self.tabla.column("carpeta", width=235)
            self.tabla.column("auto", width=110, anchor="center")
            self.tabla.pack(fill="both", expand=True)
            self.tabla.bind("<Double-1>", lambda e: self.boton_abrir_click())
            self.tabla.bind("<<TreeviewSelect>>", lambda e: self.actualizar_botones())

            # Botones en una rejilla de 4 columnas: caben en ventanas de 760 px de ancho
            marco = ttk.Frame(p)
            marco.pack(side="bottom", fill="x", pady=(8, 0), before=self.tabla)
            filas = [
                [("Montar", self.boton_montar_click,
                  "Conecta la nube como carpeta y la añade a la barra lateral del explorador."),
                 ("Desmontar", self.boton_desmontar_click,
                  "Desconecta la carpeta. Tus archivos siguen seguros en la nube. Espera a que "
                  "terminen las subidas pendientes antes de desmontar."),
                 ("Abrir en el explorador", self.boton_abrir_click,
                  "Abre la carpeta con tu explorador de archivos (también con doble clic). Si la "
                  "nube se sincroniza abre la carpeta local; si no, la monta y la abre."),
                 ("Inicio automático", self.boton_auto_click,
                  "Activa o desactiva que esta nube se monte sola al iniciar sesión.")],
                [("Ver espacio", self.boton_espacio_click,
                  "Muestra cuánto espacio usas y cuánto te queda en esa cuenta."),
                 ("Reconectar sesión", self.boton_reconectar_click,
                  "Si la nube dice que la sesión caducó o deja de responder por permisos: vuelve "
                  "a iniciar sesión en el navegador SIN borrar la conexión ni su configuración."),
                 ("Ver registro", self.boton_registro_click,
                  "Abre el registro técnico de rclone para esta nube (útil si algo falla)."),
                 ("Eliminar conexión", self.boton_eliminar_click,
                  "Olvida esta cuenta en este equipo (borra la configuración local de rclone). "
                  "NO borra ningún archivo de tu nube.")],
                [("Sincronización…", self.boton_config_sinc_click,
                  "Activa, desactiva o cambia la carpeta local y la frecuencia de sincronización "
                  "de esta nube."),
                 ("Sincronizar ahora", self.boton_sinc_ahora_click,
                  "Pide que se sincronice esta nube de inmediato.")],
            ]
            self.botones = {}
            for f, fila in enumerate(filas):
                for c, (texto, cmd, ayuda) in enumerate(fila):
                    b = ttk.Button(marco, text=texto, command=cmd)
                    b.grid(row=f, column=c, sticky="ew", padx=(0, 6), pady=2)
                    Ayuda(b, ayuda)
                    self.botones[texto] = b
            b = ttk.Button(marco, text="Equipo compartido…", command=self.boton_compartido_click)
            b.grid(row=2, column=2, sticky="ew", padx=(0, 6), pady=2)
            Ayuda(b, "Para computadores que usan varias personas con la misma cuenta (aulas): "
                     "al iniciar cada sesión se desconectan todas las nubes.")
            self.boton_icono = ttk.Button(marco, text="Iniciar icono", command=self.boton_icono_click)
            self.boton_icono.grid(row=2, column=3, sticky="ew", padx=(0, 6), pady=2)
            Ayuda(self.boton_icono, "Inicia el icono del área de notificaciones (o, sin PyGObject, "
                                    "la sincronización sin icono) si se cerró.")
            for c in range(4):
                marco.columnconfigure(c, weight=1, uniform="botones")

            # Límite de velocidad y «Actualizar», en su propia fila bajo la carpeta base
            fila_vel = ttk.Frame(p)
            fila_vel.pack(fill="x", pady=(0, 8), after=fila_base)
            ttk.Label(fila_vel, text="Velocidad máxima de las nubes:").pack(side="left")
            self.velocidad = tk.StringVar()
            actual = self.ajustes.get("bwlimit", "")
            self.velocidad.set(next((e for e, v in LIMITES_VELOCIDAD if v == actual), "Sin límite"))
            cv = ttk.Combobox(fila_vel, textvariable=self.velocidad, state="readonly", width=12,
                              values=[e for e, _ in LIMITES_VELOCIDAD])
            cv.pack(side="left", padx=6)
            cv.bind("<<ComboboxSelected>>", lambda e: self.cambiar_velocidad())
            ttk.Button(fila_vel, text="Actualizar", command=self.refrescar_lista).pack(side="right")
            Ayuda(cv, "Limita lo que usan las nubes de tu conexión a Internet (útil en la red "
                      "del colegio o con datos móviles). Se aplica al instante a las nubes "
                      "montadas y a la siguiente sincronización.")

        def nube_seleccionada(self, avisar=True):
            sel = self.tabla.selection()
            if not sel:
                if avisar:
                    messagebox.showinfo(APP_NOMBRE, "Primero selecciona una nube de la lista.")
                return None
            return sel[0]

        def refrescar_lista(self):
            self.en_segundo_plano(self._datos_lista, self._pintar_lista)

        def _datos_lista(self):
            self.ajustes = cargar_ajustes()
            icono = bandeja_en_ejecucion()
            estado_icono = leer_estado() if icono else {}
            datos = []
            for nombre, tipo in listar_remotos():
                ruta = punto_montaje(nombre, self.ajustes)
                if montaje_roto(ruta):
                    montaje = "⚠ Bloqueada"
                elif esta_montado(ruta):
                    montaje = "● Montada"
                else:
                    montaje = "○ Sin montar"
                conf = self.ajustes.get("sincronizacion", {}).get(nombre)
                if conf:
                    e = estado_icono.get("nubes", {}).get(nombre, {})
                    if not icono:
                        estado = "⚠ Icono detenido"
                    elif e.get("estado") == "sincronizando":
                        estado = "⟳ Sincronizando…"
                    elif estado_icono.get("pausado"):
                        estado = "⏸ En pausa"
                    elif e.get("estado") == "error":
                        estado = "⚠ " + (e.get("mensaje") or "Error")
                    elif e.get("estado") == "ok":
                        estado = "✔ Al día (%s)" % hace(e.get("ultima"))
                    else:
                        estado = "… Pendiente"
                    modo = "Sincronización" + (" + montaje" if montaje == "● Montada" else "")
                    datos.append((nombre, TIPOS_LEGIBLES.get(tipo, tipo), modo, estado,
                                  conf.get("carpeta", ""), "Sí (icono)"))
                else:
                    datos.append((nombre, TIPOS_LEGIBLES.get(tipo, tipo), "Montaje", montaje, ruta,
                                  "Sí" if nombre in self.ajustes["automontaje"] else "No"))
            return datos, icono

        def _pintar_lista(self, resultado):
            if isinstance(resultado, Exception):
                return
            datos, icono = resultado
            self.boton_icono.configure(text="Icono en marcha" if icono else "Iniciar icono")
            self.boton_icono.state(["disabled"] if icono else ["!disabled"])
            seleccion = self.tabla.selection()
            self.tabla.delete(*self.tabla.get_children())
            for nombre, tipo, modo, estado, ruta, auto in datos:
                self.tabla.insert("", "end", iid=nombre, text=nombre,
                                  values=(tipo, modo, estado, ruta, auto))
            for s in seleccion:
                if self.tabla.exists(s):
                    self.tabla.selection_set(s)
            if not datos:
                self.tabla.insert("", "end", iid="__vacio__", text="(ninguna)",
                                  values=("Ve a «2. Conectar una nube»", "", "", "", ""))
            self.actualizar_botones()

        def actualizar_botones(self):
            sel = self.tabla.selection()
            hay = bool(sel) and sel[0] != "__vacio__"
            for b in self.botones.values():
                b.state(["!disabled"] if hay else ["disabled"])

        def refresco_periodico(self):
            if self.cuaderno.select() == str(self.pest_mis):
                self.refrescar_lista()
            self.after(5000, self.refresco_periodico)

        def accion_montar(self, nombre, abrir=False):
            self.estado.set("Montando «%s»… (puede tardar unos segundos)" % nombre)
            self.config(cursor="watch")

            def hecho(res):
                self.config(cursor="")
                if isinstance(res, Exception):
                    res = (False, str(res))
                ok, msg = res
                if ok:
                    ruta = punto_montaje(nombre, self.ajustes)
                    integrado = anadir_marcador(ruta, nombre)
                    self.estado.set("«%s» montada en %s" % (nombre, ruta))
                    self.escribir_log("✔ " + msg)
                    if integrado:
                        self.escribir_log("✔ Añadida a la barra lateral del explorador de archivos.")
                    if abrir:
                        abrir_en_explorador(ruta)
                else:
                    self.estado.set("No se pudo montar «%s»." % nombre)
                    messagebox.showerror(APP_NOMBRE, msg)
                self.refrescar_lista()
            self.en_segundo_plano(montar, hecho, nombre, self.ajustes)

        def boton_montar_click(self):
            nombre = self.nube_seleccionada()
            if nombre:
                self.accion_montar(nombre)

        def boton_desmontar_click(self):
            nombre = self.nube_seleccionada()
            if not nombre:
                return
            ruta = punto_montaje(nombre, self.ajustes)

            def hecho(res):
                ok, msg = res if not isinstance(res, Exception) else (False, str(res))
                self.estado.set(msg.splitlines()[0])
                if not ok:
                    messagebox.showerror(APP_NOMBRE, msg)
                self.refrescar_lista()
            self.estado.set("Desmontando «%s»…" % nombre)
            self.en_segundo_plano(desmontar, hecho, ruta)

        def boton_abrir_click(self):
            nombre = self.nube_seleccionada(avisar=False)
            if not nombre or nombre == "__vacio__":
                return
            conf = self.ajustes.get("sincronizacion", {}).get(nombre)
            if conf:
                os.makedirs(conf["carpeta"], exist_ok=True)
                abrir_en_explorador(conf["carpeta"])
                return
            ruta = punto_montaje(nombre, self.ajustes)

            # Comprobar el montaje puede quedarse esperando si la red falla: en otro hilo
            def comprobar():
                return esta_montado(ruta) and not montaje_roto(ruta)

            def hecho(montada):
                if montada is True:
                    ok, msg = abrir_en_explorador(ruta)
                    if not ok:
                        messagebox.showwarning(APP_NOMBRE, msg)
                else:
                    self.accion_montar(nombre, abrir=True)
            self.en_segundo_plano(comprobar, hecho)

        def boton_auto_click(self):
            nombre = self.nube_seleccionada()
            if not nombre:
                return
            if self.ajustes.get("equipo_compartido"):
                messagebox.showinfo(APP_NOMBRE, "En modo «equipo compartido» las nubes se "
                                    "desconectan al iniciar cada sesión, así que no se pueden "
                                    "montar automáticamente.")
                return
            if nombre in self.ajustes.get("sincronizacion", {}):
                messagebox.showinfo(APP_NOMBRE, "«%s» se sincroniza con una carpeta local: el icono "
                                    "del área de notificaciones se inicia solo al entrar a tu sesión "
                                    "y la mantiene al día." % nombre)
                return
            quitar = nombre in self.ajustes["automontaje"]
            self.modificar_ajustes(lambda a: a["automontaje"].remove(nombre) if quitar
                                   else a["automontaje"].append(nombre))
            actualizar_autoarranque(self.ajustes)
            msg = ("«%s» ya no se montará al iniciar sesión." if quitar else
                   "«%s» se montará automáticamente al iniciar sesión.") % nombre
            self.estado.set(msg)
            self.refrescar_lista()

        def boton_espacio_click(self):
            nombre = self.nube_seleccionada()
            if not nombre:
                return
            self.estado.set("Consultando el espacio de «%s»…" % nombre)
            self.en_segundo_plano(espacio_remoto, lambda t: (
                self.estado.set("Listo."),
                messagebox.showinfo("Espacio en " + nombre, str(t))), nombre)

        def boton_eliminar_click(self):
            nombre = self.nube_seleccionada()
            if not nombre:
                return
            if not messagebox.askyesno(APP_NOMBRE, (
                    "¿Eliminar la conexión «%s» de este equipo?\n\n"
                    "• Se desmontará la carpeta y se quitará del explorador.\n"
                    "• Si se sincronizaba, se detiene la sincronización; la carpeta local y sus "
                    "archivos se conservan.\n"
                    "• Tus archivos en la nube NO se borran.\n"
                    "• Podrás volver a conectarla cuando quieras." % nombre), icon="warning"):
                return
            ruta = punto_montaje(nombre, self.ajustes)
            self.estado.set("Eliminando «%s»…" % nombre)
            self.config(cursor="watch")

            def trabajo():
                ok, msg = desmontar(ruta)
                if not ok:
                    return False, msg, None
                codigo, salida = eliminar_remoto(nombre)
                return True, codigo, salida

            def hecho(res):
                self.config(cursor="")
                if isinstance(res, Exception):
                    res = (False, str(res), None)
                if not res[0]:
                    self.estado.set("No se pudo eliminar «%s»." % nombre)
                    messagebox.showerror(APP_NOMBRE, res[1])
                    return
                self._fin_eliminar(nombre, ruta, res[1], res[2])
            self.en_segundo_plano(trabajo, hecho)

        def _fin_eliminar(self, nombre, ruta, codigo, salida):
            quitar_marcador(ruta)
            conf = self.ajustes.get("sincronizacion", {}).get(nombre)
            if conf:
                quitar_marcador(conf.get("carpeta", ""))

            def limpiar(a):
                if nombre in a["automontaje"]:
                    a["automontaje"].remove(nombre)
                a.get("sincronizacion", {}).pop(nombre, None)
            self.modificar_ajustes(limpiar)
            actualizar_autoarranque(self.ajustes)
            try:
                if os.path.isdir(ruta) and not os.listdir(ruta):
                    os.rmdir(ruta)
            except OSError:
                pass
            if codigo != 0:
                messagebox.showerror(APP_NOMBRE, "rclone no pudo borrar la conexión:\n" + salida)
            self.estado.set("Conexión «%s» eliminada." % nombre)
            self.refrescar_lista()

        def activar_sincronizacion(self, nombre, carpeta, intervalo, desde_conectar=False):
            """Guarda la configuración y pide al icono la primera sincronización."""
            if self.ajustes.get("equipo_compartido"):
                messagebox.showerror(APP_NOMBRE, MSG_COMPARTIDO_SIN_SINC)
                return False
            if permisos_solo_lectura(nombre):
                messagebox.showerror(APP_NOMBRE, MSG_SOLO_LECTURA_SIN_SINC)
                return False
            ruta = os.path.abspath(os.path.expanduser(carpeta.strip()))
            error = self.validar_carpeta_sinc(ruta, nombre)
            if error:
                messagebox.showerror(APP_NOMBRE, error)
                return False
            anterior = self.ajustes.get("sincronizacion", {}).get(nombre, {})
            misma = anterior.get("carpeta") == ruta
            if not (misma and anterior.get("inicializada")):
                try:
                    tiene_archivos = os.path.isdir(ruta) and bool(os.listdir(ruta))
                except OSError:
                    tiene_archivos = False
                if tiene_archivos and not messagebox.askokcancel(APP_NOMBRE, (
                        "La carpeta %s ya contiene archivos.\n\n"
                        "En la primera sincronización se combinarán con los de la nube: lo que "
                        "falte en un lado se copiará al otro y NO se borrará nada. Si un mismo "
                        "archivo es distinto en ambos lados, se conserva el más reciente." % ruta)):
                    return False
            try:
                os.makedirs(ruta, exist_ok=True)
            except OSError as e:
                messagebox.showerror(APP_NOMBRE, "No se pudo crear la carpeta:\n%s" % e)
                return False
            if anterior and not misma:
                quitar_marcador(anterior.get("carpeta", ""))
            nueva = {"carpeta": ruta, "intervalo": intervalo,
                     "inicializada": bool(misma and anterior.get("inicializada"))}
            self.modificar_ajustes(lambda a: a.setdefault("sincronizacion", {}).__setitem__(nombre, nueva))
            anadir_marcador(ruta, nombre + " (sincronizada)")
            ok, msg = iniciar_bandeja()
            if ok:
                pedir_a_bandeja("sincronizar", nombre)
            if desde_conectar:
                self.escribir_log("✔ Carpeta local: " + ruta)
                self.escribir_log("✔ Añadida a la barra lateral del explorador de archivos.")
                if ok:
                    self.escribir_log("⟳ La primera sincronización empieza ahora. Sigue su progreso en "
                                      "el icono de nube del área de notificaciones: te avisará al terminar.")
                    abrir_en_explorador(ruta)
            if not ok:
                messagebox.showwarning(APP_NOMBRE, msg + "\n\nLa configuración se guardó; la "
                                       "sincronización empezará cuando el icono pueda iniciarse.")
            self.estado.set("Sincronización de «%s» activada." % nombre)
            self.refrescar_lista()
            return True

        def boton_config_sinc_click(self):
            nombre = self.nube_seleccionada()
            if not nombre or nombre == "__vacio__":
                return
            conf = self.ajustes.get("sincronizacion", {}).get(nombre, {})
            v = tk.Toplevel(self)
            v.title("Sincronización de «%s»" % nombre)
            v.transient(self)
            marco = ttk.Frame(v, padding=14)
            marco.pack(fill="both", expand=True)
            ttk.Label(marco, wraplength=560, justify="left", text=(
                "Sincronizar guarda una copia completa de tu nube en una carpeta de este equipo. "
                "Puedes trabajar en ella sin Internet: el icono del área de notificaciones sube "
                "lo que cambies (unos segundos después) y descarga lo nuevo de la nube cada pocos "
                "minutos. Si borras un archivo en un lado, también se borra en el otro.\n\n"
                "Ocupa en tu disco lo mismo que tu nube. Si tienes poco espacio, usa «Montar».")
            ).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
            activa = tk.BooleanVar(value=bool(conf))
            ttk.Checkbutton(marco, text="Sincronizar «%s» con una carpeta de este equipo" % nombre,
                            variable=activa).grid(row=1, column=0, columnspan=3, sticky="w")
            ttk.Label(marco, text="Carpeta local:").grid(row=2, column=0, sticky="w", pady=4)
            carpeta = tk.StringVar(value=conf.get("carpeta") or carpeta_sinc_defecto(nombre))
            ttk.Entry(marco, textvariable=carpeta, width=46).grid(row=2, column=1, sticky="w", padx=6)

            def elegir():
                d = filedialog.askdirectory(parent=v, initialdir=HOME, title="Carpeta local")
                if d:
                    carpeta.set(d)
            ttk.Button(marco, text="Elegir…", command=elegir).grid(row=2, column=2)
            ttk.Label(marco, text="Buscar cambios en la nube cada:").grid(row=3, column=0, sticky="w")
            intervalo = tk.StringVar(value="%d minutos" % conf.get("intervalo", 5))
            ttk.Combobox(marco, textvariable=intervalo, state="readonly", width=12,
                         values=["%d minutos" % m for m in INTERVALOS_MIN]).grid(
                row=3, column=1, sticky="w", padx=6)
            fila = ttk.Frame(marco)
            fila.grid(row=4, column=0, columnspan=3, sticky="e", pady=(14, 0))

            def guardar():
                if activa.get():
                    if self.activar_sincronizacion(nombre, carpeta.get(), int(intervalo.get().split()[0])):
                        v.destroy()
                    return
                if conf:
                    if not messagebox.askyesno(APP_NOMBRE, (
                            "¿Dejar de sincronizar «%s»?\n\nLa carpeta %s y sus archivos se conservan "
                            "en este equipo, pero ya no se actualizarán." % (nombre, conf.get("carpeta"))),
                            parent=v):
                        return
                    quitar_marcador(conf.get("carpeta", ""))
                    self.modificar_ajustes(lambda a: a.get("sincronizacion", {}).pop(nombre, None))
                    self.estado.set("Sincronización de «%s» desactivada." % nombre)
                    self.refrescar_lista()
                v.destroy()
            ttk.Button(fila, text="Cancelar", command=v.destroy).pack(side="right")
            ttk.Button(fila, text="Guardar", style="Acento.TButton", command=guardar).pack(side="right", padx=6)
            v.wait_visibility()
            v.grab_set()

        def boton_sinc_ahora_click(self):
            nombre = self.nube_seleccionada()
            if not nombre or nombre == "__vacio__":
                return
            if nombre not in self.ajustes.get("sincronizacion", {}):
                messagebox.showinfo(APP_NOMBRE, "«%s» no está configurada para sincronizarse con una "
                                    "carpeta local. Pulsa «Sincronización…»." % nombre)
                return
            ok, msg = iniciar_bandeja()
            if not ok:
                messagebox.showerror(APP_NOMBRE, msg)
                return
            pedir_a_bandeja("sincronizar", nombre)
            self.estado.set("Sincronización de «%s» solicitada." % nombre)
            self.after(2500, self.refrescar_lista)

        def boton_registro_click(self):
            nombre = self.nube_seleccionada()
            if not nombre or nombre == "__vacio__":
                return
            for archivo in (nombre + "-sincronizacion.log", nombre + ".log"):
                ruta = os.path.join(DIR_LOGS, archivo)
                if os.path.exists(ruta):
                    abrir_en_explorador(ruta)
                    return
            messagebox.showinfo(APP_NOMBRE, "Todavía no hay registro para «%s»." % nombre)

        def cambiar_velocidad(self):
            valor = dict(LIMITES_VELOCIDAD).get(self.velocidad.get(), "")
            self.modificar_ajustes(lambda a: a.update(bwlimit=valor))
            self.en_segundo_plano(aplicar_bwlimit, None, valor)
            self.estado.set("Velocidad máxima: %s." % self.velocidad.get())

        def puerto_listo(self):
            """Comprueba que el puerto del inicio de sesión esté libre (o lo libera)."""
            if not puerto_oauth_ocupado():
                return True
            pids = procesos_config_rclone()
            if pids:
                if not messagebox.askyesno(APP_NOMBRE, (
                        "Hay un intento de conexión anterior que sigue esperando a que inicies "
                        "sesión (por ejemplo, porque se cerró el navegador antes de terminar).\n\n"
                        "¿Cancelarlo y empezar de nuevo?")):
                    return False
                cancelar_procesos_config(pids)
            if puerto_oauth_ocupado():
                messagebox.showerror(APP_NOMBRE, (
                    "Otro programa está usando el puerto %d, que rclone necesita para recibir "
                    "la autorización del navegador.\n\nCierra cualquier otra configuración de "
                    "rclone abierta (por ejemplo en una terminal) e inténtalo de nuevo." % PUERTO_OAUTH))
                return False
            return True

        def boton_reconectar_click(self):
            nombre = self.nube_seleccionada()
            if not nombre or nombre == "__vacio__":
                return
            if self.proceso_config and self.proceso_config.poll() is None:
                messagebox.showinfo(APP_NOMBRE, "Ya hay un inicio de sesión en curso. Termínalo o "
                                    "pulsa «Cancelar» en «2. Conectar una nube».")
                return
            if not self.puerto_listo():
                return
            if not messagebox.askokcancel(APP_NOMBRE, (
                    "Vamos a renovar la sesión de «%s».\n\n"
                    "1. Se abrirá tu navegador: inicia sesión con la MISMA cuenta.\n"
                    "2. Acepta los permisos y vuelve a esta ventana.\n\n"
                    "La conexión, su carpeta y su configuración se conservan." % nombre)):
                return
            self.cuaderno.select(self.pest_con)
            self.log.configure(state="normal")
            self.log.delete("1.0", "end")
            self.log.configure(state="disabled")
            self.escribir_log("Renovando la sesión de «%s»…" % nombre)
            self.escribir_log("Esperando a que inicies sesión en el navegador (tienes unos 5 minutos)…")
            self.escribir_log("Si cierras el navegador sin terminar, pulsa «Cancelar».\n")
            self.boton_conectar.state(["disabled"])
            self.boton_cancelar.state(["!disabled"])
            self.boton_url.state(["disabled"])
            self.url_autorizacion = None
            self.estado.set("Esperando la autorización en el navegador…")
            # «config update» renueva el token sin preguntas (reconnect necesita teclado)
            orden = [rclone_bin(), "config", "update", nombre, "config_refresh_token=true"]

            def trabajo():
                try:
                    self.proceso_config = subprocess.Popen(
                        orden, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, bufsize=1)
                except OSError as e:
                    self.cola.put((self.escribir_log, "Error: %s" % e))
                    self.cola.put((self.fin_reconexion, (nombre, 1)))
                    return
                for linea in self.proceso_config.stdout:
                    self.cola.put((self.linea_rclone, linea))
                self.cola.put((self.fin_reconexion, (nombre, self.proceso_config.wait())))
            threading.Thread(target=trabajo, daemon=True).start()

        def fin_reconexion(self, datos):
            nombre, codigo = datos
            self.boton_conectar.state(["!disabled"])
            self.boton_cancelar.state(["disabled"])
            self.boton_url.state(["disabled"])
            self.proceso_config = None
            if codigo != 0:
                self.estado.set("No se renovó la sesión de «%s»." % nombre)
                self.escribir_log("\n✘ No se completó (código %s). La conexión sigue como estaba." % codigo)
                messagebox.showerror(APP_NOMBRE, (
                    "No se pudo renovar la sesión. La conexión no se ha modificado.\n\n"
                    "Comprueba que iniciaste sesión con la misma cuenta y vuelve a intentarlo."))
                return
            self.escribir_log("\n✔ Sesión de «%s» renovada." % nombre)
            self.estado.set("Sesión de «%s» renovada." % nombre)
            # El montaje en marcha sigue con la sesión vieja: volver a montarlo
            if esta_montado(punto_montaje(nombre, self.ajustes)):
                if bandeja_en_ejecucion():
                    pedir_a_bandeja("remontar", nombre)
                else:
                    self.en_segundo_plano(lambda: (desmontar(punto_montaje(nombre, self.ajustes)),
                                                   montar(nombre, self.ajustes)), None)
                self.escribir_log("⟳ Volviendo a montar «%s» con la sesión nueva…" % nombre)
            if nombre in self.ajustes.get("sincronizacion", {}):
                pedir_a_bandeja("sincronizar", nombre)
            self.cuaderno.select(self.pest_mis)
            self.refrescar_lista()

        def boton_compartido_click(self):
            activo = bool(self.ajustes.get("equipo_compartido"))
            if activo:
                if messagebox.askyesno(APP_NOMBRE, (
                        "El modo «equipo compartido» está ACTIVADO.\n\n"
                        "¿Desactivarlo? Las cuentas que conectes se recordarán entre sesiones.")):
                    self.modificar_ajustes(lambda a: a.update(equipo_compartido=False))
                    self.aplicar_modo_compartido()
                    self.estado.set("Modo «equipo compartido» desactivado.")
                return
            if self.ajustes.get("sincronizacion"):
                messagebox.showinfo(APP_NOMBRE, (
                    "Primero desactiva la sincronización de todas las nubes (botón "
                    "«Sincronización…»): en un equipo compartido las copias locales quedarían al "
                    "alcance de la siguiente persona."))
                return
            if messagebox.askyesno(APP_NOMBRE, (
                    "Activa este modo si varias personas usan esta misma cuenta de Linux "
                    "(por ejemplo, en un aula).\n\n"
                    "• Al iniciar cada sesión se desmontan y OLVIDAN todas las nubes conectadas, "
                    "y se borran los archivos guardados en caché.\n"
                    "• Cada persona conecta su cuenta al empezar y puede desconectarla al terminar "
                    "desde el icono del área de notificaciones.\n"
                    "• La sincronización con carpeta local no está disponible.\n\n"
                    "Lo más seguro sigue siendo que cada persona tenga su propio usuario de Linux.\n\n"
                    "¿Activar el modo «equipo compartido»?")):
                self.modificar_ajustes(lambda a: a.update(equipo_compartido=True,
                                                          automontaje=[]))
                # Lo que se conecte en ESTA sesión no se borra al reabrir la ventana o el
                # icono; la limpieza empieza en el siguiente inicio de sesión
                marcar_sesion_limpia()
                actualizar_autoarranque(self.ajustes)
                self.aplicar_modo_compartido()
                self.estado.set("Modo «equipo compartido» activado.")

        def boton_icono_click(self):
            ok, msg = iniciar_bandeja()
            if not ok:
                messagebox.showerror(APP_NOMBRE, msg)
            self.after(2000, self.refrescar_lista)

        def cambiar_base(self):
            montadas = [n for n, _ in listar_remotos() if esta_montado(punto_montaje(n, self.ajustes))]
            if montadas:
                messagebox.showinfo(APP_NOMBRE, "Desmonta primero todas las nubes (%s) para cambiar "
                                    "la carpeta base." % ", ".join(montadas))
                return
            nueva = filedialog.askdirectory(initialdir=HOME, title="Elige la carpeta base para tus nubes")
            if nueva:
                for nombre, _ in listar_remotos():
                    quitar_marcador(punto_montaje(nombre, self.ajustes))
                self.modificar_ajustes(lambda a: a.update(carpeta_base=nueva))
                self.base.set(nueva)
                self.refrescar_lista()

        # =========================== PESTAÑA AYUDA ===========================
        def construir_ayuda(self):
            texto = tk.Text(self.pest_ayu, wrap="word", font=("TkDefaultFont", 10), padx=8, pady=8)
            barra = ttk.Scrollbar(self.pest_ayu, command=texto.yview)
            texto.configure(yscrollcommand=barra.set)
            barra.pack(side="right", fill="y")
            texto.pack(fill="both", expand=True)
            texto.insert("1.0", TEXTO_AYUDA % {
                "base": self.ajustes["carpeta_base"], "logs": DIR_LOGS,
                "auto": ARCHIVO_AUTOSTART, "ajustes": ARCHIVO_AJUSTES})
            texto.configure(state="disabled")

    app = Aplicacion()
    if problemas_limpieza:
        app.after(500, lambda: messagebox.showwarning(APP_NOMBRE, (
            "No se pudieron desconectar estas nubes del usuario anterior: %s.\n\n"
            "Cierra los programas que usan sus archivos o cierra y vuelve a abrir la sesión."
            % ", ".join(problemas_limpieza))))
    app.mainloop()
    if app.proceso_config and app.proceso_config.poll() is None:
        app.proceso_config.terminate()        # no dejar una conexión colgada
    return 0


TEXTO_AYUDA = """\
PREGUNTAS FRECUENTES

¿Qué es «montar» una nube?
  Es hacer que tu Google Drive, OneDrive o Dropbox aparezca como una carpeta más \
del equipo (en %(base)s). Los archivos no se descargan todos: se bajan cuando los \
abres y se suben cuando los guardas.

¿Dónde aparece en mi explorador de archivos?
  En la barra lateral («Marcadores» o «Lugares») de Nautilus, Nemo, Caja, Thunar, \
PCManFM y Dolphin, y en los diálogos de «Abrir/Guardar» de las aplicaciones. Si no \
aparece de inmediato, cierra y vuelve a abrir el explorador.

¿Montar o sincronizar?
  MONTAR no ocupa espacio en el disco, pero necesita Internet: solo los archivos \
abiertos recientemente quedan en caché (24 horas).
  SINCRONIZAR guarda una copia completa en una carpeta local (por defecto en \
~/NubesSincronizadas) que funciona sin Internet. El icono de nube del área de \
notificaciones sube lo que cambies unos segundos después y descarga lo nuevo de la \
nube cada pocos minutos (rclone bisync).

El icono del área de notificaciones
  Muestra si se está sincronizando (flechas), si todo está al día (✔), si hay \
archivos nuevos (punto naranja), si está en pausa o si hubo un error. Su menú permite \
abrir la carpeta local o la nube en el navegador, sincronizar ahora, pausar y ver \
los archivos añadidos recientemente. Se inicia solo al entrar a tu sesión.
  En GNOME necesitas la extensión «AppIndicator and KStatusNotifierItem Support» \
(Ubuntu ya la trae). En KDE, XFCE, Cinnamon, MATE, LXQt y Budgie funciona directamente.

¿Qué pasa si cambio el mismo archivo en dos sitios?
  Se conserva la versión más reciente y la otra se guarda junto a ella con un número \
añadido al nombre, para que no pierdas nada.

Se detuvo «por seguridad»
  Si una sincronización fuera a borrar más de la mitad de los archivos, rclone se \
detiene. Revisa la carpeta y usa «Reparar» en el menú del icono: une ambas copias sin \
borrar nada.

Al cerrar esta ventana, ¿se desmontan las nubes?
  No. Siguen montadas hasta que pulses «Desmontar», cierres sesión o apagues el equipo.

¿Es seguro? ¿Dónde se guardan mis credenciales?
  Nunca escribes tu contraseña aquí: inicias sesión en la web oficial del servicio. \
rclone guarda un «token» de acceso en ~/.config/rclone/rclone.conf. Puedes cifrar \
ese archivo con «rclone config» → «s) Set configuration password».

La carpeta aparece «Bloqueada» (⚠)
  rclone se cerró inesperadamente. Pulsa «Desmontar» y luego «Montar». Si sigue \
fallando, revisa los registros en %(logs)s

Error «/dev/fuse» o «fusermount not found»
  Instala el paquete fuse3 y carga el módulo con: sudo modprobe fuse
  En Alpine Linux: doas apk add fuse3 && doas modprobe fuse && echo fuse | doas tee -a /etc/modules

Google dice «Esta aplicación no está verificada»
  Es normal con el cliente compartido de rclone. Pulsa «Configuración avanzada» → \
«Ir a rclone (no seguro)». Si prefieres evitarlo, crea tu propio ID de cliente y \
ponlo en «Opciones avanzadas».

Cuentas institucionales (colegio, universidad, secretaría, empresa)
  Muchas instituciones exigen que un administrador apruebe las aplicaciones que \
acceden a tus archivos. Al conectar, elige «Permisos: Mínimos»:
  • OneDrive: solo tu propio OneDrive (sin SharePoint ni lo compartido contigo).
  • Google Drive: solo los archivos que subas desde este equipo.
  Con permisos mínimos algunas instituciones permiten conectar sin aprobación. Si \
aun así la piden, solicita a sistemas que aprueben «rclone» con esos permisos, o que \
registren una aplicación propia y te den su «ID de cliente» (ponlo en «Opciones \
avanzadas» al conectar). No intentes saltarte el bloqueo: es una norma de tu institución.

Computadores compartidos (aulas)
  Si varias personas usan la MISMA cuenta de Linux, activa «Equipo compartido…» en \
«Mis nubes» (o instala con «./instalar.sh --equipo-compartido»). Al iniciar cada \
sesión se desconectan y olvidan todas las nubes y se borra la caché; al terminar, \
cada persona puede usar «Desconectar todas las cuentas» en el menú del icono. Lo más \
seguro sigue siendo que cada persona tenga su propio usuario de Linux.
  IMPORTANTE: desconectar las nubes no cierra tu sesión de Google o Microsoft en el \
navegador. Al terminar, cierra sesión también en Firefox/Chrome, o usa una ventana \
privada para iniciar sesión.

«La sesión caducó»
  Pasa a veces con OneDrive y Google (cambio de contraseña, permisos revocados…). En \
«Mis nubes» selecciona la nube y pulsa «Reconectar sesión»: vuelves a iniciar sesión \
en el navegador y la conexión conserva su carpeta y su configuración.

Velocidad máxima
  En «Mis nubes» o en el menú del icono puedes limitar lo que usan las nubes de tu \
conexión (1, 5 o 10 MB/s), útil en la red del colegio o con datos móviles.

Permisos de solo lectura
  Una conexión de solo lectura no puede sincronizarse (habría que subir cambios a la \
nube): úsala con «Montar como carpeta».

Archivos que usa esta aplicación
  Ajustes ............... %(ajustes)s
  Inicio automático ..... %(auto)s
  Registros y estado .... %(logs)s
  Configuración rclone .. ~/.config/rclone/rclone.conf

Uso desde la terminal
  nubes-rclone --montar-auto      monta las nubes marcadas para inicio automático
  nubes-rclone --desmontar-todo   desmonta todas las nubes
  nubes-rclone --bandeja          inicia el icono del área de notificaciones
  nubes-rclone --sincronizar-servicio   sincroniza sin icono (sin PyGObject)
"""


def main(argv):
    if "--version" in argv:
        print("%s %s" % (APP_NOMBRE, VERSION))
        return 0
    if "--montar-auto" in argv:
        return montar_automaticamente()
    if "--desmontar-todo" in argv:
        return desmontar_todo()
    if "--sincronizar-servicio" in argv:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import nubes_sinc
        return nubes_sinc.main()
    if "--bandeja" in argv:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import nubes_bandeja
        return nubes_bandeja.main()
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    return iniciar_interfaz()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
