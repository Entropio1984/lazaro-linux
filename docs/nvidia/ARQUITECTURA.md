# Controlador propietario de NVIDIA en Lázaro Linux

Estado: **opción A confirmada en la RTX 3060** (27-11-2026, ver la
sección 7). Este documento fija la arquitectura y los criterios con que se
probó. Se actualiza con los resultados reales de
`nvidia/prueba-viabilidad.sh` en cada equipo de prueba.

## 1. El problema de fondo

Lázaro Linux usa musl. Todo lo que NVIDIA entrega para el espacio de
usuario está compilado contra glibc:

| Pieza | Qué es | Quién la carga |
|---|---|---|
| `nvidia_drv.so`, `libglxserver_nvidia.so` | controlador 2D y GLX de Xorg | **el proceso de Xorg** |
| `libnvidia-egl-gbm.so`, `nvidia-drm_gbm.so` | GBM para compositores Wayland | **el proceso del compositor** |
| `libEGL_nvidia.so`, `libGLX_nvidia.so`, `libnvidia-glcore.so` | OpenGL y EGL | cada aplicación con OpenGL |
| `nvidia_icd.json` (apunta a `libGLX_nvidia.so`) | Vulkan | cada aplicación con Vulkan |
| `libcuda.so`, `libnvidia-encode.so`, `libnvcuvid.so` | CUDA, NVENC, NVDEC | cada aplicación que los use |
| `nvidia-smi`, `nvidia-persistenced`, `nvidia-settings` | programas | procesos propios |

Una biblioteca glibc no se puede cargar dentro de un proceso musl: el
cargador, el TLS, `pthread`, `malloc`, los símbolos versionados
(`memcpy@GLIBC_2.14`...) y los internos (`__libc_*`, `__register_atfork`,
`dlvsym`) son distintos. `gcompat` traduce lo básico, y alcanza para
programas sencillos, pero no para estas bibliotecas, que además cargan
otras (`libnvidia-tls`, `libnvidia-glsi`) con supuestos de glibc.

**La consecuencia que manda todo el diseño:** el proceso que dibuja la
pantalla (Xorg o el compositor Wayland) carga piezas de NVIDIA, así que
**tiene que ser un proceso glibc**. No basta con aislar las aplicaciones.

El kernel no tiene este problema: los módulos no usan libc y se compilan
con el `gcc` y `make` de Alpine sin cambios.

## 2. Opciones evaluadas

### A. Servidor gráfico glibc en un sysroot aislado (la elegida)

Un sistema glibc mínimo en `/opt/lazaro-nvidia/raiz` con Xorg y el
espacio de usuario de NVIDIA. LightDM (musl, del sistema) arranca ese Xorg
en lugar del suyo. El escritorio (XFCE, MATE, LXQt, IceWM), Firefox y el
resto siguen siendo los programas musl de Alpine, que se conectan a Xorg
por el socket `/tmp/.X11-unix`, como siempre. El protocolo X no sabe de
libc.

- **2D y escritorio**: acelerados por el propio `nvidia_drv.so` en Xorg.
  Resolución nativa, varios monitores, `xrandr`, cambio de modo.
- **Juegos, Steam, Proton y aplicaciones con 3D**: desde Flatpak, que ya
  es glibc. Flatpak instala solo la extensión
  `org.freedesktop.Platform.GL.nvidia-<versión>` que corresponde al
  módulo cargado (la lee de `/sys/module/nvidia/version`). Lázaro ya trae
  Flathub.
- **CUDA, NVENC, `nvidia-smi`**: dentro del sysroot y en Flatpak.
- **Aplicaciones musl de Alpine con OpenGL**: usan `llvmpipe` (Mesa por
  software). Es el precio de la arquitectura y hay que dejarlo escrito.
- **El sistema base no cambia**: nada glibc entra en `/usr` ni en
  `/lib`. Quitar el sysroot y los módulos deja el sistema como estaba.

### B. Compositor musl en el host y aceleración solo vía Flatpak

El servidor gráfico musl usa `nvidia-drm` en modo KMS (`modeset=1`) con
dibujo por software, y solo las aplicaciones Flatpak usan la GPU.

Probablemente no funciona. En X11, el `libGLX_nvidia` del cliente exige la
extensión GLX de NVIDIA en el servidor, y sin ella libglvnd elige Mesa.
En Wayland, un compositor sin GPU (renderizador pixman de wlroots) no
puede importar los buffers de la GPU que manda `egl-wayland`. La prueba la
descarta o la confirma en pocos minutos, así que se incluye como paso
opcional.

### C. Controladores libres: `nouveau` con GSP + NVK y Zink

Para Turing en adelante, Mesa ya tiene Vulkan (NVK) y OpenGL sobre Vulkan
(Zink), y el kernel usa el firmware GSP de NVIDIA. Todo es musl nativo,
sin sysroot. No es el controlador propietario y rinde menos en juegos,
pero es el **plan B** si A no pasa la prueba en la RTX 3060, y es lo que
ya usa Lázaro hoy.

### Descartadas

- **`gcompat` o `libc6-compat` solos**: ver la sección 1. La prueba lo
  intenta con `nvidia-smi` solo para dejar el resultado documentado.
- **Todo el escritorio dentro del sysroot**: funciona, pero convierte a
  Lázaro en una distribución glibc con Alpine debajo. Duplica el
  escritorio y las traducciones, y pierde el sentido del proyecto.

## 3. Qué tarjeta va por dónde

Basado en las generaciones que ya reconoce `lazaro-graficas`:

| Generación | Ejemplo | Módulo | Rama | Wayland | Salida |
|---|---|---|---|---|---|
| Turing, Ampere, Ada, Blackwell | RTX 3060 | abierto (`kernel-open`) | actual | sí (GBM) | propietario |
| Maxwell, Pascal, Volta | GTX 970, 1060 | cerrado | 580 (la última para ellas) | sí | propietario |
| Kepler | GT 740 | cerrado | 470 (sin soporte, con parches) | no en la práctica | propietario legacy, solo Xorg |
| Fermi y anteriores | GT 540M | ninguno | 390 (sin soporte, sin Vulkan) | no | `nouveau` |
| Portátiles Optimus | | sigue en `nouveau` hasta probar PRIME offload | | | `nouveau` |

Blackwell solo funciona con el módulo abierto. Los portátiles Optimus
quedan fuera de la primera versión: necesitan PRIME render offload y la
configuración de dos GPU, y ninguno de los equipos de prueba lo cubre
salvo la GT 540M, que no lo soporta.

## 4. Piezas

### 4.1 Módulos del kernel

- Se extraen del mismo `.run` que el espacio de usuario: **el módulo y las
  bibliotecas tienen que ser exactamente de la misma versión**, o nada
  arranca.
- Se compilan para cada kernel instalado (`linux-lts` y `linux-lazaro`)
  contra su paquete `-dev`. Para recompilar al actualizar el kernel, el
  candidato es `akms` (soporte de módulos externos de Alpine); si no
  sirve, un disparador de `apk` propio como el de `lazaro-kernel`.
- El firmware GSP (`gsp_*.bin`) va en `/lib/firmware/nvidia/<versión>/`.
  No es el de `linux-firmware-nvidia`, que es el de `nouveau`.
- `nouveau` en la lista negra, `nvidia-drm modeset=1 fbdev=1`, y los
  módulos en el initramfs (`mkinitfs`) para que la consola use la
  resolución nativa desde el arranque.

### 4.2 Sysroot glibc

- Base: **Debian estable**, creada con `debootstrap`. Se elige Debian y no
  una distribución continua (Void, Arch) porque la ABI de Xorg tiene que
  quedarse quieta durante años para la rama 470.
- Contenido mínimo: `xserver-xorg-core`, `xserver-xorg-input-libinput`,
  libglvnd y las herramientas de prueba. Unos 250 MB.
- El espacio de usuario de NVIDIA se instala dentro con el propio `.run`
  (`--no-kernel-module --no-install-libglvnd`).
- Montajes hacia el sysroot: `/dev`, `/proc`, `/sys`, `/run/udev` (Xorg
  descubre teclado y ratón con el udev de Lázaro, que es eudev) y
  `/tmp/.X11-unix` (para que los clientes musl encuentren la pantalla).
  En la prueba se hace con `chroot`. En la versión final, con
  `bubblewrap` o un espacio de nombres de montaje, para que no queden
  montajes sueltos.

### 4.3 Integración con LightDM y OpenRC

- LightDM: `xserver-command=/usr/libexec/lazaro/nvidia-xorg`, un envoltorio
  que entra al sysroot y ejecuta su Xorg.
- OpenRC: `nvidia-persistenced` (dentro del sysroot), y carga de módulos
  antes de `lightdm`.
- Reglas de udev para crear `/dev/nvidia*` y `/dev/nvidia-uvm` (lo que
  normalmente hace `nvidia-modprobe`).

### 4.4 Wayland

Va después de Xorg. Mismo esquema: el compositor (Sway o labwc) se instala
en el sysroot y lo arranca LightDM. Las aplicaciones musl dibujan por
software y mandan buffers de memoria compartida, y las Flatpak usan la
GPU.

## 5. Criterios de la prueba (RTX 3060)

La arquitectura A se confirma si en la RTX 3060 pasan todos estos puntos:

1. El módulo abierto compila con las herramientas de Alpine y carga
   (`/proc/driver/nvidia/version`).
2. `nvidia-smi` del sysroot ve la tarjeta.
3. El Xorg del sysroot arranca en un TTY con `nvidia_drv.so`, y ve el
   teclado y el ratón.
4. `glxinfo` dentro del sysroot dice `OpenGL vendor string: NVIDIA`, y
   `vulkaninfo` muestra la tarjeta.
5. Un programa musl del sistema (un `xterm` de Alpine) se abre en ese
   Xorg.
6. (Opcional) Un Flatpak con `GL.nvidia` usa la tarjeta en ese Xorg.

Y se anota, sin que sea condición: qué hace `gcompat` con `nvidia-smi`,
qué renderizador ven las aplicaciones musl, cuánto ocupa el sysroot y
cuánto tarda en compilar el módulo.

Si falla el 1, se revisan las herramientas de compilación. Si falla el 3,
el 4 o el 5, se pasa a la opción C.

## 6. Límites que hay que asumir

- Es una configuración que NVIDIA no soporta. Funciona porque cada pieza
  corre en la libc para la que se compiló.
- Las aplicaciones musl de Alpine no tienen aceleración 3D ni decodificación
  de video por NVIDIA. Las que la necesiten tienen que venir de Flatpak.
- Las ramas 470 y 390 ya no reciben correcciones de NVIDIA: cada kernel
  LTS nuevo puede romper la compilación del módulo de la 470.
- Secure Boot exigiría firmar los módulos. Queda fuera por ahora.
- **Escritorios que componen con OpenGL** (Plasma con KWin, GNOME con
  Mutter): su gestor de ventanas es un programa musl, así que compone con
  `llvmpipe` aunque Xorg sea el de NVIDIA. En la prueba, Plasma con el
  módulo de NVIDIA cargado (sesión Wayland) abrió "excesivamente lento":
  KWin no encuentra GBM ni EGL de Mesa para la tarjeta y compone por
  software. XFCE, MATE, LXQt e
  IceWM componen con XRender o no componen, y no tienen ese problema. Para
  Plasma y GNOME hay dos salidas: llevar KWin o Mutter al sysroot (como el
  compositor Wayland de 4.4), o que el instalador recomiende otro
  escritorio cuando active el controlador propietario.
- Con el módulo de NVIDIA instalado, `nouveau` no se carga: si el Xorg del
  sysroot no arranca, el escritorio musl queda sin aceleración. La vuelta
  atrás automática a `nouveau` (paso 4 del plan) es obligatoria.

## 7. Resultados

### RTX 3060 (GA106, Ampere), Alpine v3.24, kernel 6.18.65-0-lts

| Criterio | Resultado |
|---|---|
| 1. Módulo abierto compila y carga | **Pasa** con la 620.73.04: 35 s con gcc 15.2.0 y musl. La 580.95.05 **no** compila: es anterior al 6.18, que cambió `pci_resize_resource` a 4 argumentos. |
| 2. `nvidia-smi` en el sysroot | **Pasa** |
| 3. Xorg del sysroot con `nvidia_drv.so` | **Pasa** |
| 4. OpenGL y Vulkan en el sysroot | **Pasan**, los dos con NVIDIA |
| 5. Cliente musl en ese Xorg | **Pasa** (`xdpyinfo` de Alpine) |
| 6. Flatpak con `GL.nvidia` | No probado todavía |

Anotaciones:

- Las aplicaciones musl ven `llvmpipe (LLVM 22.1.3, 256 bits)`, como se
  esperaba.
- Xorg del sysroot: `nvidia_drv.so` con aceleración 2D, monitor a
  2560x1440 en DFP-1, OpenGL 4.6.0 NVIDIA 620.73.04. Solo avisos menores
  (sin D-Bus del sistema ni `acpid` dentro del sysroot).
- **`nvidia-smi` funciona con `gcompat`**, sin glibc (aunque informa
  `CUDA UMD Version: N/A`, porque solo se copió `libnvidia-ml`). Es más de lo que se
  esperaba (sección 1). No cambia la decisión, porque Xorg y las
  bibliotecas de OpenGL son mucho más exigentes, pero vale la pena probar
  más adelante hasta dónde llega `gcompat`, por ejemplo con
  `nvidia-persistenced` o `libcuda`.
- El sysroot Debian trixie ocupa 520 MB. Tardó 67 minutos por la lentitud
  de `deb.debian.org` desde el equipo de prueba, y el primer intento de
  `debootstrap` falló por una descarga (el reintento lo resolvió). Para la versión final
  conviene un espejo cercano o un sysroot ya preparado que se descargue de
  una vez.
- La versión del controlador no puede ser fija: tiene que salir de una
  tabla por kernel y rama, o de la última de producción de NVIDIA. Mientras
  tanto, la prueba usa por defecto la 620.73.04, la que funcionó aquí.
