# Lázaro Nubes

Interfaz gráfica sencilla, en español, para usar **rclone** en Linux y conectar
**Google Drive**, **Microsoft OneDrive** y **Dropbox** como carpetas normales
dentro del explorador de archivos.

- Asistente paso a paso con mensajes explicativos (y ayudas al pasar el ratón).
- Inicio de sesión en la web oficial de cada servicio: la aplicación nunca ve tu contraseña.
- Monta cada nube en `~/Nubes/<nombre>` y la añade a la barra lateral de
  Nautilus, Nemo, Caja, Thunar, PCManFM y Dolphin, y a los diálogos «Abrir/Guardar».
- **Sincronización con una carpeta local** (`rclone bisync`): copia completa que
  funciona sin Internet, en `~/NubesSincronizadas/<nombre>`.
- **Icono en el área de notificaciones** que muestra si está sincronizando, si todo
  está al día, si hay errores o si está en pausa; avisa cuando llegan archivos
  nuevos y su menú permite abrir la carpeta local o la nube en el navegador,
  sincronizar ahora, pausar y ver los archivos añadidos recientemente.
- Montaje automático al iniciar sesión (autoarranque XDG, sin systemd: funciona con OpenRC, runit, etc.).
- Muestra el espacio usado/libre de cada cuenta.
- Solo usa Python 3 + Tkinter para la ventana y PyGObject (Gio) para el icono,
  así que funciona en cualquier distribución: Debian/Ubuntu/Mint, Fedora,
  Arch/Manjaro, openSUSE, Void, Solus, Gentoo y **Alpine Linux** (BusyBox/musl).

## Instalación

```bash
chmod +x instalar.sh
```

```bash
./instalar.sh
```

El instalador detecta tu gestor de paquetes (`apk`, `apt`, `dnf`, `yum`,
`pacman`, `zypper`, `xbps`, `eopkg`, `emerge`), instala `rclone`, `fuse3`,
`python3-tk`, PyGObject y `xdg-utils` (pidiendo permisos con `sudo`, `doas` o `su`),
crea el lanzador **Lázaro Nubes** en el menú de aplicaciones y deja en marcha el
icono del área de notificaciones (que también se iniciará solo en cada sesión).

En Alpine además carga el módulo `fuse` y lo añade a `/etc/modules`.

Ejecútalo con tu usuario normal, **no con sudo**: pedirá la contraseña solo cuando
la necesite. Si tu distribución no trae rclone, o trae una versión anterior a la
1.66, ofrece descargar el binario oficial y **verifica su suma SHA-256** antes de
instalarlo.

Para computadores de aula donde varias personas usan la misma cuenta:

```bash
./instalar.sh --equipo-compartido
```

Si ya tienes las dependencias, o no tienes permisos de administrador:

```bash
./instalar.sh --sin-dependencias
```

Para desinstalar (no borra tus conexiones, tus carpetas sincronizadas ni tus archivos en la nube):

```bash
./instalar.sh --desinstalar
```

También puedes ejecutarla sin instalar: `python3 nubes_rclone.py`

## Uso

1. **Requisitos**: comprueba que tienes todo; si falta algo te muestra la orden exacta para tu distribución.
2. **Conectar una nube**: elige el servicio, pon un nombre, elige si quieres
   *montarla* o *sincronizarla con una carpeta local* y pulsa *Conectar*.
   Se abre el navegador, inicias sesión, aceptas y listo.
3. **Mis nubes**: monta, desmonta, abre en el explorador, configura la
   sincronización, sincroniza ahora, consulta el espacio, **renueva la sesión**
   («Reconectar sesión», sin borrar la conexión), limita la **velocidad máxima**
   (también desde el menú del icono) o elimina la conexión.

### Montar o sincronizar

| | Montar | Sincronizar |
|---|---|---|
| Espacio en disco | Casi nada (caché) | Lo mismo que tu nube |
| Sin Internet | Solo lo abierto hace poco | Todo |
| Cambios locales | Se suben al guardar | Se suben ~15 s después |
| Cambios en la nube | Aparecen en ~1 min | Cada 2–60 min (configurable) |

### Icono del área de notificaciones

| Icono | Significado |
|---|---|
| Nube con ✔ | Todo al día |
| Nube con flechas | Sincronizando |
| Nube con punto naranja | Llegaron archivos nuevos (se quita al abrir el menú) |
| Nube gris con pausa | Sincronización en pausa |
| Nube con ⚠ roja | Error (el menú explica qué pasó y ofrece «Reparar») |

Clic izquierdo: abre la ventana (otro clic la cierra). Clic derecho: menú. Clic central: sincronizar todo.

Funciona en KDE Plasma, XFCE, Cinnamon, MATE, LXQt, Budgie, Waybar y otros
paneles compatibles con StatusNotifierItem; en bandejas X11 antiguas usa GTK
como respaldo. **En GNOME** hace falta la extensión *AppIndicator and
KStatusNotifierItem Support* (Ubuntu ya la incluye).

Desde la terminal:

```bash
nubes-rclone --montar-auto
```

```bash
nubes-rclone --desmontar-todo
```

```bash
nubes-rclone --bandeja
```

Sin PyGObject (sistemas mínimos o gestores de ventanas sin bandeja) la
sincronización funciona igual, sin icono. También se puede pedir expresamente:

```bash
nubes-rclone --sincronizar-servicio
```

### Equipos compartidos

Con el modo «equipo compartido» (botón en «Mis nubes» o `--equipo-compartido` al
instalar), cada inicio de sesión desconecta y olvida todas las nubes y borra la
caché, para que la siguiente persona no acceda a las cuentas de la anterior. Se
hace **una sola vez por sesión**: si el icono se reinicia a mitad de clase no se
borra lo que el docente acaba de conectar. Al terminar, el menú del icono ofrece
«Desconectar todas las cuentas»: si algún programa retiene archivos abiertos,
cierra igualmente el proceso de rclone y avisa en rojo si algo no se pudo
desconectar. En este modo no se permite sincronizar con carpeta local ni montar
automáticamente. Lo más seguro sigue siendo un usuario de Linux por persona.

**Importante:** desconectar las nubes no cierra la sesión de Google o Microsoft
en el navegador. En un aula, ciérrala también en Firefox/Chrome o usa una
ventana privada para iniciar sesión.

### Seguridad

- Ajustes en `~/.config/nubes-rclone` con permisos `0700`/`0600`.
- Sockets de control, bloqueos y peticiones en `$XDG_RUNTIME_DIR/nubes-rclone` (privado).
- El `client_secret` propio no aparece en la lista de procesos durante el inicio de
  sesión (se pasa por el entorno); al terminar se guarda en `rclone.conf` con una orden
  que dura unos milisegundos.
- La caché de archivos abiertos se limita a 2 GB (`cache_max` en `ajustes.json`).

## Archivos

| Qué | Dónde |
|---|---|
| Conexiones de rclone (tokens) | `~/.config/rclone/rclone.conf` |
| Ajustes de la aplicación | `~/.config/nubes-rclone/ajustes.json` |
| Inicio automático | `~/.config/autostart/nubes-rclone-automontaje.desktop` y `nubes-rclone-bandeja.desktop` |
| Registros | `~/.cache/nubes-rclone/<nombre>.log` y `<nombre>-sincronizacion.log` |
| Estado de la sincronización | `~/.cache/nubes-rclone/estado.json` |
| Sockets, bloqueos y peticiones | `$XDG_RUNTIME_DIR/nubes-rclone/` |
| Marcadores GTK / KDE | `~/.config/gtk-3.0/bookmarks`, `~/.local/share/user-places.xbel` |

## Notas

- Se monta con `--vfs-cache-mode full`, así cualquier programa puede abrir y
  editar archivos; los cambios se suben en segundo plano. Espera a que terminen
  antes de desmontar o apagar.
- Si Dolphin está abierto mientras se añade el marcador, puede que tengas que
  reiniciarlo para verlo.
- La sincronización usa `rclone bisync`: la primera vez une ambas copias sin
  borrar nada; después, lo que borres en un lado se borra en el otro. Si un
  archivo cambió en ambos lados se conserva el más reciente y el otro se
  renombra. rclone se detiene por seguridad si fuera a borrar más de la mitad
  de los archivos.
- Las funciones de recuperación automática de bisync necesitan rclone 1.66 o
  posterior; con versiones anteriores la sincronización funciona igual, pero
  con menos protección ante cortes.
