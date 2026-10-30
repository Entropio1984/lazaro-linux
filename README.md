# Lázaro Linux

**Tu hardware aún tiene pulso.**

ISO de Alpine Linux con sesión live (escritorio XFCE) e instalador gráfico
Calamares, pensada para revivir portátiles antiguos. Arranca en equipos
con BIOS y con UEFI. Al instalar se elige uno de los escritorios que Alpine
soporta oficialmente y, al final, se ejecuta `desktop-postinstall.sh`
sin hacer preguntas. Ese script vive en su propio repositorio,
[alpine-desktop-setup](https://github.com/Entropio1984/alpine-desktop-setup),
y se descarga al compilar la ISO.

## Descargar

La última ISO probada está en la Release
[en desarrollo](https://github.com/Entropio1984/lazaro-linux/releases/tag/en-desarrollo):
baja el archivo `.iso` (y, si quieres comprobar que llegó entero, su
suma `.sha256`). No hace falta cuenta de GitHub. Se actualiza sola cada
vez que cambia la rama principal y pasan las pruebas automáticas.
Todavía no es una versión final: pruébala en una máquina virtual o en
un equipo de sobra.

## Qué vas a ver al instalar

Al encender desde la ISO aparece el logo de Lázaro con un pulso, y
luego el escritorio de prueba (XFCE) con el instalador abierto. El
instalador (Calamares) pregunta, en este orden:

1. **Idioma**, **zona horaria** y **teclado**.
2. **Escritorio**: XFCE (recomendado, ya preseleccionado), MATE, LXQt,
   XFCE con Wayland (experimental), GNOME, KDE Plasma, Sway o
   **Sin escritorio (solo consola)**. Esta última opción deja solo el
   sistema básico en modo texto, sin programas gráficos, navegador ni
   impresoras; sirve para servidores o personas con experiencia.
3. **Software adicional**, con casillas. Firefox e impresoras se
   instalan siempre.
   - Programas de Alpine: **Fastfetch**, **Btop**, **VLC** y
     **LibreOffice** (en el idioma elegido), desmarcados, y
     **YouTube ligero** (marcado, ver abajo).
   - Aplicaciones Flatpak: **Flatpak + tienda Flathub** (marcada por
     defecto, para que la tienda ofrezca miles de programas),
     **OnlyOffice**, **Google Chrome** y **Brave**. Se instalan solas
     después del primer arranque con internet; marcar una de ellas
     instala también Flatpak.
4. **Disco** y **usuario**. En la pantalla del usuario, la casilla
   **Iniciar sesión automáticamente** (desmarcada) hace que el equipo
   entre directo al escritorio sin pedir la contraseña. Para quitarlo
   después: borrar `/etc/lazaro/autologin` y reiniciar.

XFCE, MATE, LXQt, Sway, XFCE Wayland y "Sin escritorio" se instalan sin
internet, desde la propia ISO. GNOME y KDE Plasma se descargan (no caben
en el límite de 2 GB de la ISO).
Los demás escritorios se descargan, igual que el software adicional.

**Tarjetas NVIDIA.** Antes de cargar el controlador de una NVIDIA
(nouveau), la sesión de prueba revisa qué tarjeta es. Lo carga en los
portátiles con dos gráficas (para poder apagar la NVIDIA) y en las
tarjetas de 2012 (Kepler) en adelante. Con las más antiguas (Tesla y
Fermi) o una que no reconoce, como gráfica principal, no lo carga:
algunas dan pantalla negra o bloqueos. La sesión usa entonces la imagen
básica y muestra un aviso. La opción "modo gráfico seguro" del menú no
carga ningún controlador.

Para forzar la decisión se agrega `lazaro.nvidia=seguro` (no cargar
nouveau) o `lazaro.nvidia=activa` (cargarlo) en el menú de arranque de
la ISO, justo al encender desde la memoria USB. El sistema instalado
respeta esa elección.

- **Equipo con UEFI** (menú de GRUB, espera 5 segundos): detén el menú
  con las flechas en "Lazaro Linux - Tu hardware aun tiene pulso", pulsa
  **e**, baja a la línea que empieza con `linux`, ve al final con la
  tecla Fin, escribe un espacio y `lazaro.nvidia=seguro`, y arranca con
  **Ctrl+X** o **F10**.
- **Equipo con BIOS** (aparece `boot:`, espera unos 3 segundos): escribe
  `lazaro lazaro.nvidia=seguro` y pulsa Enter. `lazaro` es el nombre de
  la opción normal del menú.

### YouTube ligero

Abre YouTube sin navegador: en el menú, sección Multimedia (Sonido y
video), aparece **YouTube**. Busca con Pipe Viewer (ventana sencilla) y
reproduce con mpv en **480p H.264 a 30 cuadros**, el formato que menos
procesador gasta en equipos viejos (sin VP9, AV1 ni 60 cuadros). Viene
en el USB (~18 MB) y no necesita Electron, Flatpak ni Node. Detalle de
los archivos que deja y cómo ajustarlo: sección "YouTube ligero" del
[README de alpine-desktop-setup](https://github.com/Entropio1984/alpine-desktop-setup#youtube-ligero).

- **Si deja de funcionar** (YouTube cambia seguido): actualizar
  `doas apk upgrade yt-dlp yt-dlp-ejs pipe-viewer`. Si la versión de
  Alpine aún no trae el arreglo, se puede tomar la de edge:
  `doas apk upgrade --repository https://dl-cdn.alpinelinux.org/alpine/edge/community yt-dlp yt-dlp-ejs yt-dlp-ejs-rt-quickjs`.
  Para ver el error: `yt-dlp -v "DIRECCION-DEL-VIDEO"`.
- **Si el video se traba** (procesador de un núcleo): bajar a 360p. En
  Pipe Viewer, menú de preferencias, resolución 360 (se guarda al
  cerrar la ventana); para mpv solo, cambiar `480` por `360` en
  `/etc/mpv/mpv.conf`.

### Si el escritorio no abre

En algunos equipos (poca memoria, o una tarjeta gráfica sin controlador)
la sesión live puede no llegar al escritorio. Si a los 5 minutos no
abrió, o se cerró, la pantalla pasa a la consola de texto con un aviso:
entra como `lazaro` (no pide contraseña) y escribe
`doas lazaro-instalar-texto`. Es un instalador con menús que se maneja
con el teclado (flechas, barra espaciadora y Enter), hace las mismas
preguntas que el gráfico (disco, escritorio, programas, idioma, teclado,
zona horaria y usuario) y la misma instalación. No borra nada hasta que
confirmas el resumen. Para wifi, antes de abrirlo:
`nmcli device wifi connect "NOMBRE DE LA RED" password "CLAVE"`
(con las comillas).

Con el sistema ya instalado, el arranque también muestra el pulso
(Plymouth). Por ahora no aparece en dos casos: con GNOME (su pantalla de
inicio todavía no se lleva bien con él) y sin escritorio, donde el
arranque se ve en texto.

## Cómo está armada

| Pieza | Dónde | Qué hace |
|---|---|---|
| Versión de Alpine y de Calamares | `config.env` | Un solo lugar para cambiar de versión |
| Origen de `desktop-postinstall.sh` | `config.env` (`POSTINSTALL_URL`) | Se descarga en cada compilación |
| Calamares | `paquetes/calamares/APKBUILD` | Alpine no lo empaqueta, así que se compila |
| Perfil de la ISO | `perfil/mkimg.lazaro.sh` | Lo usa `mkimage.sh` de aports |
| Sesión live | `perfil/genapkovl-lazaro.sh` + `live/` | Usuario `lazaro`, inicio automático, Calamares |
| Revisión de tarjetas gráficas | `live/usr/sbin/lazaro-graficas` | Decide si cargar nouveau antes del escritorio |
| Recomendación según el equipo | `live/usr/sbin/lazaro-recomendar` | Escritorio y programas preseleccionados en Calamares según memoria, gráfica y disco |
| Pasos de instalación | `live/usr/sbin/lazaro-instalar` | Usa `setup-disk` y `setup-desktop` de Alpine |
| Pantallas del instalador | `live/etc/calamares/modules/` | Escritorio, oficina, aplicaciones, disco, usuario |
| Pantalla de arranque | `live/usr/share/plymouth/themes/lazaro/` | El logo con el pulso (Plymouth) |
| Pruebas | `pruebas/qemu.sh` | Arranque live e instalación en QEMU, BIOS y UEFI |
| Comprobaciones dentro del sistema de prueba | `live/usr/share/lazaro/pruebas/` | Solo las usa la instalación desatendida |
| Compilación automática | `.github/workflows/lazaro-iso.yml` | Estable + edge, en cada cambio y cada lunes |

### Qué pasa al instalar

1. Calamares pregunta idioma, zona horaria, teclado, escritorio,
   oficina, aplicaciones, disco y usuario.
2. Calamares particiona y monta el disco (ext4; partición EFI en UEFI).
3. `lazaro-instalar base`: `setup-disk` instala el sistema base, el kernel,
   el firmware del hardware detectado y GRUB (BIOS o UEFI, con la ruta de
   respaldo `EFI/boot/bootx64.efi` para firmwares viejos).
4. Calamares crea el usuario (grupo `wheel`, con `doas`).
5. `lazaro-instalar escritorio`: `setup-desktop <escritorio>` (con
   "Sin escritorio" no se instala ninguno).
6. `lazaro-instalar ajustes`: idioma, teclado, zona horaria y
   `desktop-postinstall.sh` con las opciones elegidas (oficina,
   aplicaciones) y las premarcadas de su menú. Si no hay internet, el
   script queda programado para el primer arranque con red (servicio
   `lazaro-primer-arranque`).

## Compilar

En cualquier Linux con Docker:

```sh
./build.sh
```

La ISO queda en `salida/`. La primera vez tarda bastante
porque compila Calamares; después lo toma de `cache/`.

Para probar la siguiente versión de Alpine sin tocar archivos:

```sh
ALPINE_BRANCH=edge ./build.sh
```

Para cambiarla de forma permanente, edita `ALPINE_BRANCH` en
`config.env`.

Para probar cambios de `desktop-postinstall.sh` antes de subirlos a su
repositorio, usa una copia local:

```sh
LAZARO_SCRIPT=../alpine-desktop-setup/desktop-postinstall.sh ./build.sh
```

## Probar

Solo en máquinas virtuales o en un equipo de sobra: el instalador borra
el disco que se elija.

```sh
./pruebas/qemu.sh live salida/lazaro-linux-0.1-3.24-x86_64.iso bios
./pruebas/qemu.sh instalar salida/lazaro-linux-0.1-3.24-x86_64.iso uefi xfce con-red
```

Las capturas de pantalla y los registros quedan en
`pruebas/resultados/`.

### Pruebas automáticas

En cada cambio, GitHub compila la ISO y la prueba en máquinas virtuales
(QEMU). Cada prueba corre con la versión estable de Alpine y con la
siguiente (edge):

| Prueba | Arranque | Escritorio | Internet | Qué comprueba |
|---|---|---|---|---|
| Sesión live | BIOS | XFCE | Sí | El instalador se abre, ve el disco, la revisión de gráficas corrió y el portapapeles compartido funciona |
| Sesión live | UEFI | XFCE | Sí | Lo mismo, en un equipo UEFI |
| Sin escritorio | BIOS | (Xorg no arranca) | No | En la consola aparece el aviso del instalador en modo texto, y la live trae `dialog` |
| Instalación | BIOS | XFCE | No | Se instala solo desde la ISO y el sistema arranca con su pantalla de inicio y el pulso |
| Instalación | UEFI | XFCE | Sí | Además: Flathub queda listo y la pantalla de inicio recuerda la resolución que eligió el usuario |
| Instalación | UEFI | KDE Plasma | Sí | Lo mismo con Plasma |
| Instalación | BIOS | GNOME | Sí | Lo mismo con GNOME (reinicia una vez y mide la pantalla de inicio) |
| Instalación | BIOS | Sway | Sí | Su pantalla de inicio (gtkgreet) en el idioma elegido, se puede entrar, y arrancan la barra, el wifi, el agente de contraseñas y la lista de atajos |
| Instalación | UEFI | LXQt | Sí | La sesión queda en el idioma elegido |
| Instalación | BIOS | MATE | Sí | La pantalla de inicio recuerda la resolución y la sesión queda en el idioma elegido |
| Instalación | UEFI / BIOS | MATE, LXQt, XFCE Wayland | No | Se instalan solos desde la ISO y el sistema arranca con su pantalla de inicio |
| Instalación | BIOS | Sin escritorio | No | Arranca en modo texto, sin pantalla de inicio gráfica |

Las máquinas virtuales no tienen NVIDIA, así que las decisiones de la
revisión de gráficas se prueban aparte con `pruebas/graficas.sh`, que
simula 13 equipos (el K53SV, PCs con tarjetas de cada generación, dos
NVIDIA, la elección forzada y el modo gráfico seguro). Lo mismo pasa con
la recomendación del instalador: `pruebas/recomendacion.sh` simula
equipos con distinta memoria, gráfica y disco.

## Versiones probadas

| Alpine | Calamares | Estado |
|---|---|---|
| v3.24 | 3.4.3 | Se prueba en QEMU con las pruebas de la tabla de arriba |
| edge | 3.4.3 | Las mismas pruebas, como aviso temprano (no bloquean) |

## Pendiente

- Probar en el ASUS K53SV (BIOS antiguo, Intel HD 3000 + NVIDIA GT 540M).
- Cifrado de disco (desactivado por ahora).
