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

La última ISO probada está en la versión
[en desarrollo](https://github.com/Entropio1984/lazaro-linux/releases/tag/en-desarrollo)
(archivo `.iso` y su suma `.sha256`). Se actualiza sola cada vez que
cambia la rama principal y pasan las pruebas. Todavía no es una versión
final: pruébala en una máquina virtual o en un equipo de sobra.

## Cómo está armada

| Pieza | Dónde | Qué hace |
|---|---|---|
| Versión de Alpine y de Calamares | `config.env` | Un solo lugar para cambiar de versión |
| Origen de `desktop-postinstall.sh` | `config.env` (`POSTINSTALL_URL`) | Se descarga en cada compilación |
| Calamares | `paquetes/calamares/APKBUILD` | Alpine no lo empaqueta, así que se compila |
| Perfil de la ISO | `perfil/mkimg.lazaro.sh` | Lo usa `mkimage.sh` de aports |
| Sesión live | `perfil/genapkovl-lazaro.sh` + `live/` | Usuario `lazaro`, inicio automático, Calamares |
| Pasos de instalación | `live/usr/sbin/lazaro-instalar` | Usa `setup-disk` y `setup-desktop` de Alpine |
| Pruebas | `pruebas/qemu.sh` | Arranque live e instalación en QEMU, BIOS y UEFI |
| Compilación automática | `.github/workflows/lazaro-iso.yml` | Estable + edge, en cada cambio y cada lunes |

### Qué pasa al instalar

1. Calamares pregunta idioma, zona horaria, teclado, **escritorio**
   (XFCE preseleccionado), disco y usuario.
2. Calamares particiona y monta el disco (ext4; partición EFI en UEFI).
3. `lazaro-instalar base`: `setup-disk` instala el sistema base, el kernel,
   el firmware del hardware detectado y GRUB (BIOS o UEFI, con la ruta de
   respaldo `EFI/boot/bootx64.efi` para firmwares viejos).
4. Calamares crea el usuario (grupo `wheel`, con `doas`).
5. `lazaro-instalar escritorio`: `setup-desktop <escritorio>`.
6. `lazaro-instalar ajustes`: idioma, teclado, zona horaria y
   `desktop-postinstall.sh` con las opciones premarcadas de su menú.
   Si no hay internet, el script queda programado para el primer
   arranque con red (servicio `lazaro-primer-arranque`).

XFCE se instala sin internet desde la propia ISO. Los demás escritorios
(MATE, LXQt, xfce-wayland, GNOME, Plasma, Sway) se descargan.

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

## Versiones probadas

| Alpine | Calamares | Estado |
|---|---|---|
| v3.24 | 3.4.3 | Pasa en QEMU: live BIOS/UEFI, instalación BIOS sin red y UEFI con red |
| edge | 3.4.3 | Pasa las mismas pruebas (aviso temprano, no bloquea) |

## Pendiente

- Probar en el ASUS K53SV (BIOS antiguo, Intel HD 3000 + NVIDIA GT 540M).
- Capturas reales de cada escritorio en el selector (hoy son tarjetas).
- Cifrado de disco (desactivado por ahora).
