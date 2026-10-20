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
3. **Oficina**: **Ninguno** (por defecto, la instalación queda más
   liviana y puedes agregarla después), **LibreOffice** o
   **OnlyOffice**. OnlyOffice se instala desde Flathub, así que también
   instala Flatpak. Las dos necesitan internet.
4. **Aplicaciones**: **Lo esencial + tienda Flathub** (por defecto:
   Firefox, impresoras y Flatpak, para que la tienda de aplicaciones
   ofrezca miles de programas de Flathub), **Solo lo esencial** (sin
   Flatpak) o **Lo esencial + Flathub + Chrome**.
5. **Disco** y **usuario**.

XFCE y "Sin escritorio" se instalan sin internet, desde la propia ISO.
Los demás escritorios se descargan, igual que la oficina y Flathub.

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
| Sesión live | BIOS | XFCE | Sí | El instalador se abre, ve el disco y el portapapeles compartido funciona |
| Sesión live | UEFI | XFCE | Sí | Lo mismo, en un equipo UEFI |
| Instalación | BIOS | XFCE | No | Se instala solo desde la ISO y el sistema arranca con su pantalla de inicio y el pulso |
| Instalación | UEFI | XFCE | Sí | Además: Flathub queda listo y la pantalla de inicio recuerda la resolución que eligió el usuario |
| Instalación | UEFI | KDE Plasma | Sí | Lo mismo con Plasma |
| Instalación | BIOS | GNOME | Sí | Lo mismo con GNOME (reinicia una vez y mide la pantalla de inicio) |
| Instalación | BIOS | Sway | Sí | Su pantalla de inicio (gtkgreet) en el idioma elegido, se puede entrar, y arrancan la barra, el wifi, el agente de contraseñas y la lista de atajos |
| Instalación | UEFI | LXQt | Sí | La sesión queda en el idioma elegido |
| Instalación | BIOS | MATE | Sí | La pantalla de inicio recuerda la resolución y la sesión queda en el idioma elegido |
| Instalación | BIOS | Sin escritorio | No | Arranca en modo texto, sin pantalla de inicio gráfica |

## Versiones probadas

| Alpine | Calamares | Estado |
|---|---|---|
| v3.24 | 3.4.3 | Se prueba en QEMU con las pruebas de la tabla de arriba |
| edge | 3.4.3 | Las mismas pruebas, como aviso temprano (no bloquean) |

## Pendiente

- Probar en el ASUS K53SV (BIOS antiguo, Intel HD 3000 + NVIDIA GT 540M).
- Capturas reales de cada escritorio en el selector (hoy son tarjetas).
- Cifrado de disco (desactivado por ahora).
