# Lázaro Linux

**Tu hardware aún tiene pulso.**

Lázaro Linux es un sistema operativo gratuito para darle una segunda vida
a computadores y portátiles viejos. Se instala desde una memoria USB, en
español, con unas pocas preguntas sencillas, y deja el equipo listo para
navegar por internet, escribir documentos, abrir PDF, ver YouTube e
imprimir.

> **Todavía está en desarrollo.** Ya se instala bien en varios equipos
> reales, pero pruébalo primero en un equipo de sobra o en una máquina
> virtual, y guarda una copia de tus archivos antes de instalar.

## ¿Qué tiene de distinto?

- **Hecho para equipos viejos.** Está basado en
  [Alpine Linux](https://alpinelinux.org), uno de los sistemas más
  livianos que existen. Al arrancar mira tu equipo y te recomienda el
  escritorio que mejor le va según la memoria (con menos de 2 GB, LXQt;
  de 2 a 4 GB, XFCE) y la tarjeta gráfica. Si el disco es pequeño,
  desmarca la tienda Flathub para no llenarlo.
- **Sin pasos técnicos.** No hay que escribir comandos ni configurar nada
  a mano: idioma, teclado, sonido, wifi, impresoras y controladores de
  video quedan listos solos. Firefox viene siempre (salvo si eliges
  "Sin escritorio").
- **Funciona sin internet.** La edición Completa trae todo dentro del USB
  y se instala en un equipo que no tiene red. Si instalas sin internet
  con la edición Ligera, lo que falta se completa la primera vez que el
  equipo se conecte (ver el [paso 7](#paso-7-el-primer-arranque)).
- **YouTube ligero.** Un reproductor de YouTube que no usa el navegador y
  gasta mucho menos procesador, para que los videos no se traben en
  equipos viejos.
- **Tarjetas NVIDIA antiguas.** Revisa qué tarjeta tienes y decide solo
  si es seguro activarla. Si no, usa una imagen básica en lugar de dejarte
  la pantalla negra.
- **Siempre hay un plan B.** Si el escritorio no llega a abrir, aparece
  un instalador en modo texto que hace lo mismo con el teclado. Y si
  algo falla, el comando `lazaro-diagnostico` arma un informe para pedir
  ayuda.
- **Afinado para tu equipo.** Al instalar, el
  [Afinador](#afinador-que-el-equipo-responda-mejor) ajusta el sistema
  según tu procesador, tu memoria y tus discos para que no se congele con
  muchas pestañas abiertas ni al copiar a un pendrive. Todo se puede
  quitar con un clic.
- **Avisa de las actualizaciones.** Un icono en la barra te avisa cuando
  hay actualizaciones, y se instalan con un clic.
- **La tienda de aplicaciones lista.** Si la marcas, queda la tienda
  Flathub con miles de programas, y puedes elegir de entrada OnlyOffice,
  Google Chrome o Brave.

## ¿Funciona en mi equipo?

- **Procesador de 64 bits** (x86_64). Casi todos los equipos desde 2008
  lo son. Los muy antiguos de solo 32 bits (por ejemplo, muchos
  netbooks con Intel Atom N270 o N280) no sirven.
- **Memoria (RAM):** 2 GB o más es lo cómodo. Con menos puede funcionar
  con LXQt, pero la sesión de prueba podría no llegar al escritorio; en
  ese caso usa el instalador en modo texto (ver
  [Problemas comunes](#problemas-comunes)).
- **Arranque BIOS o UEFI:** sirven los dos, también los equipos muy viejos.
- **Una memoria USB** de 4 GB para la edición Ligera o de 8 GB para la
  Completa.

Ya se probó en equipos reales como un Lenovo ideapad 110 (Celeron, 4 GB),
un HP Compaq CQ50 (Sempron de un núcleo) y PCs con tarjetas NVIDIA de
varias épocas.

## ¿Qué edición descargo?

| | **Ligera** | **Completa** |
|---|---|---|
| Tamaño | menos de 2 GB | unos 4,6 GB |
| ¿Necesita internet al instalar? | Para GNOME, KDE Plasma y las aplicaciones de Flathub, sí | No, nunca (solo Google Chrome) |
| Escritorios sin internet | XFCE, MATE, LXQt, Sway, XFCE Wayland | Los 7, en todos los idiomas |
| Firmware (controladores de wifi y otros) | El de red, completo | Todo |
| Módems USB 3G/4G, ADSL (PPPoE), internet del celular por cable o Bluetooth (los módems 3G/4G y el Bluetooth, en el sistema instalado) | Sí | Sí |
| Descargar | [GitHub](https://github.com/Entropio1984/lazaro-linux/releases/tag/en-desarrollo) o [SourceForge](https://sourceforge.net/projects/lazaro-linux/files/Ligera/) | [SourceForge](https://sourceforge.net/projects/lazaro-linux/files/Completa/) |

**Si dudas, elige la Ligera**: descarga más rápido y alcanza para la
mayoría. Elige la Completa si el equipo no va a tener internet o si la
conexión es lenta. No hace falta crear ninguna cuenta para descargar.

## Manual de Lázaro

Además de esta guía hay un **manual completo en PDF**, con todo lo que
hace falta para instalar y usar Lázaro en el día a día. Viene dentro de
la ISO (icono **Manual de Lázaro** en el escritorio de la sesión de prueba
y en el menú del sistema instalado) y se descarga suelto junto a cada
ISO. Su código (LaTeX) está en la carpeta [`manual/`](manual/LEEME.md).

## Guía de instalación paso a paso

### Paso 1: descargar

Descarga el archivo `.iso` de la edición que elegiste y, en la misma
carpeta, el archivo `.sha256` que está a su lado. La ISO es el "disco"
de Lázaro: un solo archivo con todo el sistema adentro.

### Paso 2: comprobar que la descarga llegó entera (recomendado)

Una descarga cortada o dañada es la causa más común de que un USB no
arranque. Hazlo **antes** de grabar el USB. Abre una terminal en la
carpeta de la descarga y escribe:

- **En Linux:** `sha256sum -c lazaro-linux-*.sha256`
  (debe decir `La suma coincide` o `OK`).
- **En Windows** (PowerShell): `Get-FileHash .\lazaro-linux-*.iso`
  y compara el número largo con el que aparece dentro del archivo
  `.sha256` (puedes abrirlo con el Bloc de notas).

### Paso 3: preparar la memoria USB

Esto **borra todo lo que tenga la memoria USB**. Usa uno de estos
programas gratuitos:

- **[balenaEtcher](https://etcher.balena.io)** (Windows, Mac y Linux), el
  más sencillo: eliges la ISO, eliges el USB y pulsas "Flash".
- **[Rufus](https://rufus.ie)** (Windows): elige la ISO y, si pregunta, la
  opción **"Escribir en modo imagen DD"**.
- **[Ventoy](https://www.ventoy.net)**: deja copiar varias ISO en el mismo
  USB. Después de copiar la ISO, usa siempre **"Quitar el dispositivo de
  forma segura"** antes de sacar el USB: si lo sacas de golpe, la copia
  puede quedar dañada y el equipo no arranca. Copia también el archivo
  `.sha256` al USB: así puedes repetir el paso 2 sobre la copia que quedó
  en él.

### Paso 4: arrancar el equipo desde el USB

Con el USB conectado, enciende el equipo y pulsa repetidas veces la tecla
del **menú de arranque** apenas aparece el logo de la marca. Luego elige
el USB en la lista.

| Marca | Tecla habitual |
|---|---|
| Asus | Esc o F8 |
| Acer | F12 |
| Dell | F12 |
| HP / Compaq | Esc y luego F9 |
| Lenovo | F12, o el botón pequeño "Novo" al lado del de encendido |
| Toshiba | F12 |
| Sony Vaio | F11 o el botón "Assist" |
| PC de escritorio | F8, F11 o F12 |

Si no aparece el USB, entra a la configuración del equipo (suele ser F2
o Supr) y, en la sección "Boot", pon el USB primero. En algunos equipos
con UEFI también hay que desactivar "Secure Boot".

Aparece un menú con dos opciones. Espera unos segundos o pulsa Enter en
la primera, **Lázaro Linux**. Usa **modo gráfico seguro** solo si la
primera se queda en negro.

### Paso 5: la sesión de prueba

Primero aparece el logo de Lázaro con un pulso y, al rato, un escritorio
con el instalador abierto. Esta es la **sesión de prueba (live)**: todo
corre desde la memoria del equipo y no se toca el disco. Puedes
cerrar el instalador, probar el wifi, el sonido y el navegador, y volver
a abrirlo desde el menú de aplicaciones: **Instalar Lázaro Linux**.

Lo que guardes aquí se pierde al apagar.

### Paso 6: instalar

El instalador pregunta, en este orden:

1. **Idioma, zona horaria y teclado.** Elige "Español" y tu país.
2. **Escritorio**: es el aspecto y el menú del sistema. Ya viene marcado
   el que Lázaro recomienda para tu equipo; si no sabes cuál elegir,
   déjalo así.

   | Escritorio | Para quién |
   |---|---|
   | **XFCE** (recomendado) | Rápido y parecido a Windows. Bueno para casi todos |
   | **LXQt** | El más liviano, para equipos con muy poca memoria |
   | **MATE** | Clásico y estable, similar a XFCE |
   | **KDE Plasma** | El más completo y vistoso; pide un equipo más nuevo |
   | **GNOME** | Moderno y diferente a Windows; pide un equipo más nuevo |
   | **XFCE Wayland** | XFCE con tecnología nueva, en prueba |
   | **Sway** | Para usuarios avanzados que usan mucho el teclado |
   | **Sin escritorio** | Solo pantalla de texto, para servidores |

3. **Software adicional**: casillas para agregar programas. Si no sabes,
   deja lo que viene marcado.
   - **Fastfetch** y **Btop**: muestran datos y consumo del equipo.
   - **VLC**: reproduce casi cualquier video o música.
   - **LibreOffice**: procesador de textos, hojas de cálculo y
     presentaciones (como Word, Excel y PowerPoint).
   - **YouTube ligero**: ver abajo.
   - **Flatpak + tienda Flathub**: una tienda con miles de programas.
   - **OnlyOffice** (otra alternativa a Office, muy parecida en su
     aspecto), **Google Chrome** y **Brave** (navegadores). En la edición
     Ligera se instalan solos unos minutos después del primer arranque
     con internet.
4. **Disco**: **se borra el disco que elijas**, con todo lo que tenga.
   Si el equipo tiene Windows u otro sistema y quieres conservarlo, el
   instalador puede ofrecer la opción de instalar a su lado, pero
   guarda antes una copia de tus archivos.
5. **Usuario**: tu nombre, el nombre del equipo y una contraseña. La
   casilla **Iniciar sesión automáticamente** hace que el equipo entre
   directo al escritorio sin pedir la contraseña (para quitarlo
   después: `doas rm /etc/lazaro/autologin` y reiniciar).

Revisa el resumen y pulsa **Instalar**. Puede tardar desde unos minutos
hasta más de una hora en equipos lentos o si descarga cosas de internet.
Al terminar, reinicia y saca el USB.

### Paso 7: el primer arranque

- Si marcaste aplicaciones de Flathub, se instalan solas en segundo plano
  cuando haya internet. Dales unos minutos.
- Si instalaste **sin internet con la Ligera**, falta la configuración
  final, y el equipo arranca en una **pantalla de texto** con un aviso
  (no es un error). Conecta el cable de red, o entra con tu usuario y
  contraseña y conecta el wifi escribiendo
  `nmcli device wifi connect "NOMBRE DE LA RED" --ask` (te pide la
  clave). En unos minutos termina sola y aparece la pantalla de inicio;
  entra desde ahí. No hace falta reiniciar.
- Para instalar más programas, abre la **tienda de aplicaciones** desde
  el menú (Discover en Plasma y LXQt, GNOME Software en los demás).
- Cuando haya actualizaciones, un icono en la barra te avisa; al hacer
  clic se abre **Actualizar el sistema**, que solo pide tu contraseña.
  (En KDE Plasma se actualiza desde Discover.)

## YouTube ligero

En el menú, sección Multimedia (Sonido y video), aparece **YouTube**.
Busca con una ventana sencilla (Pipe Viewer) y reproduce con mpv en
**480p**, el formato que menos procesador gasta. No necesita navegador.
Detalles: sección "YouTube ligero" del
[README de alpine-desktop-setup](https://github.com/Entropio1984/alpine-desktop-setup#youtube-ligero).

- **Si el video se traba** (procesador de un solo núcleo): en Pipe
  Viewer, menú de preferencias, resolución 360. Se guarda al cerrar la
  ventana.
- **Si deja de funcionar** (YouTube cambia seguido): abre una terminal y
  escribe `doas apk upgrade yt-dlp yt-dlp-ejs pipe-viewer`. Si aún no
  hay arreglo en la versión de Alpine, se puede tomar el de la versión en
  desarrollo:
  `doas apk upgrade --repository https://dl-cdn.alpinelinux.org/alpine/edge/community yt-dlp yt-dlp-ejs yt-dlp-ejs-rt-quickjs`.

## Problemas comunes

**El equipo no arranca desde el USB, o se detiene con un error.**
Revisa que la descarga esté bien con el
[paso 2](#paso-2-comprobar-que-la-descarga-llegó-entera-recomendado) y
graba el USB otra vez (o usa otro USB). Con Ventoy, repite el paso 2
sobre la copia del USB: si no coincide o da "error de entrada/salida",
esa copia está dañada.

**La pantalla se queda en negro.** Reinicia y elige **modo gráfico
seguro** en el menú del paso 4. Pasa sobre todo con tarjetas NVIDIA
viejas; ver [Tarjetas NVIDIA](#tarjetas-nvidia).

**El escritorio no abre.** Si a los 5 minutos no apareció, la pantalla
pasa sola a modo texto con un aviso. Entra como `lazaro` (no pide
contraseña) y escribe `doas lazaro-instalar-texto`. Es el mismo
instalador, con menús que se manejan con las flechas, la barra
espaciadora y Enter, y no borra nada hasta que confirmas el resumen. Para
conectar el wifi antes, escribe (con las comillas):
`nmcli device wifi connect "NOMBRE DE LA RED" password "CLAVE"`.

**No hay wifi.** Algunos portátiles tienen un botón o una combinación de
teclas (por ejemplo Fn + F2) para encender el wifi; revisa que esté
encendido. Si sigue sin aparecer ninguna red, pide ayuda con el
[informe de diagnóstico](#diagnóstico-pedir-ayuda).

**Wifi Broadcom en la sesión de prueba.** Muchos portátiles de 2008 a
2015 traen una tarjeta Broadcom que solo funciona con el controlador de
Broadcom, que es cerrado. En la sesión de prueba (antes de instalar) ese
wifi no aparece: conéctate por cable o comparte el internet del celular
por USB. Al instalar, Lázaro detecta la tarjeta y deja puesto ese
controlador (tarda unos minutos más); en el sistema instalado el wifi
ya funciona. Con la edición Ligera, para esto hace falta internet
durante la instalación (por cable o el celular por USB); la Completa
trae todo lo necesario.

**Falta un controlador (impresora, huellas, wifi viejo...).** Lázaro
revisa el equipo al instalar y deja puesto lo que necesita: impresoras
HP, Epson, Brother y Samsung, escáneres, lectores de huellas y de
tarjetas (DNI electrónico), el sonido de los portátiles Intel nuevos,
el ahorro de batería y el firmware que le falte a cualquier pieza. Si
después conectas algo que necesita un controlador, aparece un aviso; el
programa **Controladores** del menú hace la misma revisión cuando
quieras. Algunos wifi muy viejos (Broadcom b43, Intel PRO/Wireless
2100/2200, Prism54) necesitan un firmware que no se puede incluir sin
más: el aviso te pide permiso para descargarlo o, en el caso de Intel
(que viene en el USB), que aceptes su licencia. En la sesión de prueba
el aviso solo ofrece eso, para que el wifi funcione antes de instalar;
lo demás (impresoras, huellas...) se instala solo al instalar.

**La hora está mal en el primer arranque.** Se corrige sola en unos
minutos al conectarse a internet.

### Tarjetas NVIDIA

NVIDIA no ofrece su controlador oficial para este sistema, así que
Lázaro usa el controlador libre (nouveau). Antes de activarlo revisa qué
tarjeta es:

- **GeForce 8 o más nuevas**: lo activa. También en los portátiles con
  dos gráficas (Intel o AMD + NVIDIA), para poder apagar la NVIDIA.
- **Más antiguas** (GeForce FX, 6 y 7), o una **desconocida** que maneja
  la pantalla sola: usa una imagen básica y muestra un aviso, para
  evitar pantalla negra o bloqueos.

Si aun así falla, puedes forzar la decisión al arrancar desde el USB:

- **Menú gris con dos opciones (UEFI)**: con las flechas, ponte en la
  primera opción y pulsa **e**. Baja hasta la línea que empieza con
  `linux`, ve al final con la tecla Fin, escribe un espacio y
  `lazaro.nvidia=seguro`, y arranca con **Ctrl+X** o **F10**.
- **Pantalla negra que dice `boot:` (BIOS)**: escribe
  `lazaro lazaro.nvidia=seguro` y pulsa Enter.

Usa `lazaro.nvidia=activa` en lugar de `seguro` para forzar el
controlador. El sistema instalado recuerda esta elección.

## Herramientas de Lázaro

Lázaro trae tres herramientas propias para cuidar el equipo. Las tres se
abren desde el menú de aplicaciones o desde una **terminal** (búscala como
"Terminal" en el menú), y **se actualizan solas** con las actualizaciones
normales del sistema (ver
[Actualizaciones de las herramientas](#actualizaciones-de-las-herramientas)). Cuando una orden empieza con `doas`, te pide **tu
contraseña** (la que elegiste al instalar); mientras la escribes no se ve
nada en la pantalla, es normal: escríbela y pulsa Enter.

### Afinador: que el equipo responda mejor

El afinador revisa tu equipo (procesador, memoria, discos) y ajusta el
sistema para que vaya más suelto, sobre todo con poca memoria. **Al
instalar Lázaro ya queda aplicado lo recomendado para tu equipo**: no
tienes que hacer nada. Esta sección es para ver qué hizo, quitarlo o
cambiar la opción avanzada.

**Qué ajusta** (solo lo que le sirve a tu equipo):

| Ajuste | Para qué sirve |
|---|---|
| **Respuesta del escritorio** | El sistema atiende antes a las ventanas y al ratón aunque esté ocupado (por ejemplo, actualizando) |
| **Memoria** | Evita que el equipo se congele cuando se acaba la memoria por tener muchas pestañas abiertas |
| **Discos y pendrives** | Copiar un archivo grande a un pendrive no congela el escritorio |
| **Páginas gigantes** | Con 4 GB de memoria o menos, ahorra memoria |
| **Procesador** | En procesadores viejos, sube la velocidad en cuanto hay trabajo |

Además revisa que estén activas la memoria comprimida (zram) y las
mejoras de disco que deja puestas la configuración final.

**Paso a paso, con el menú:**

1. Abre el menú de aplicaciones y busca **Afinador** (está en
   Sistema o Configuración).
2. Arriba ves la lista de ajustes: ✔ quiere decir que ya está puesto,
   ○ que se puede poner y · que tu equipo no lo necesita.
3. Elige una opción y pulsa **Aceptar**:
   - **Aplicar lo recomendado**: pone los ajustes que le sirven a tu
     equipo.
   - **Quitar los ajustes**: deja todo como venía en Alpine.
   - **Protecciones del procesador (avanzado)**: ver más abajo.
   - **Kernel Lázaro (experimental)**: ver
     [Kernel Lázaro](#kernel-lázaro-experimental).
   - **Ver el informe del hardware**: muestra lo que encontró en tu
     equipo.
4. Te pide tu contraseña. Algunos ajustes se notan **después de
   reiniciar**.

**Paso a paso, con la terminal:**

```sh
lazaro-afinador --revisar          # qué ajustes hay y cuáles están puestos
lazaro-afinador --perfil           # informe del hardware del equipo
doas lazaro-afinador --aplicar     # poner lo recomendado
doas lazaro-afinador --deshacer    # quitarlo todo
```

**Protecciones del procesador (opción avanzada, apagada de fábrica).**
Los procesadores tienen fallos de diseño conocidos (con nombres como
Spectre y Meltdown) y el sistema los tapa con unas protecciones que lo
frenan un poco: en procesadores Intel Core de 2ª a 7ª generación (de
2011 a 2017, aproximadamente), entre un 5 % y un 15 %. Se pueden apagar
para ganar esa velocidad, **pero entonces una página web maliciosa podría
leer datos de otros programas, como contraseñas**. Hazlo solo en un
equipo que no se use para navegar, el banco o el correo. Se apaga desde
el Afinador o con `doas lazaro-afinador --mitigaciones si`, y se vuelve a
encender con `doas lazaro-afinador --mitigaciones no`. En ambos casos
hay que reiniciar.

**Si algo va peor después de un ajuste**, quítalos con **Quitar los
ajustes** (o `doas lazaro-afinador --deshacer`) y reinicia: el equipo
queda exactamente como venía. Ningún ajuste del afinador puede impedir
que el equipo arranque.

### Kernel Lázaro (experimental)

El **kernel** es la parte central del sistema, la que habla con el
hardware. Lázaro usa de fábrica el de Alpine. Si quieres, puedes cambiarlo
por el **kernel Lázaro**: es el mismo kernel de Alpine, con el mismo
código y las mismas actualizaciones de seguridad, pero:

- sin las piezas que solo usan los servidores y los centros de datos
  (redes especiales, discos de servidor) ni la información de
  depuración, así que pesa menos;
- con el escritorio más atento al ratón y al teclado aunque el equipo
  esté ocupado.

La mejora es pequeña y se nota más en equipos lentos. **El kernel de
Alpine se queda siempre instalado como respaldo.**

**Paso a paso:**

1. Conéctate a internet.
2. Abre el **Afinador** desde el menú y elige **Kernel Lázaro
   (experimental)**.
3. Pulsa **Instalar y probar** y escribe tu contraseña. Tarda unos
   minutos.
4. Pulsa **Reiniciar ahora**. Ese arranque es **de prueba**:
   - Si el equipo enciende bien, el kernel Lázaro queda como el de
     siempre. No tienes que hacer nada más.
   - Si se queda colgado o en negro, apágalo (mantén pulsado el botón de
     encendido) y vuelve a encenderlo: **arranca solo con el kernel de
     Alpine**, como antes.
5. Para ver en qué quedó, abre otra vez **Kernel Lázaro
   (experimental)**: dice si está en uso, esperando la prueba o si la
   prueba falló.

Las actualizaciones del kernel Lázaro llegan con las normales del
sistema (el aviso de actualizaciones), y después de cada una el primer
arranque vuelve a ser de prueba.

**Para volver al kernel de Alpine:** en el mismo lugar, pulsa **Volver al
kernel de Alpine** y reinicia. Si el equipo no llega al escritorio, en el
menú negro que aparece al encender, usa las flechas para elegir la línea
que termina en **lts** (es el kernel de Alpine; puede estar dentro de
**Advanced options**) y pulsa Enter.

**Con la terminal:**

```sh
lazaro-kernel --estado            # si está instalado y en qué quedó la prueba
doas lazaro-kernel --instalar     # instalar y preparar el arranque de prueba
doas lazaro-kernel --quitar       # volver al kernel de Alpine
```

### Actualizaciones de las herramientas

Las herramientas de Lázaro (Afinador, Controladores, Diagnóstico y el
kernel Lázaro) llegan por el **repositorio de Lázaro**: un lugar en
internet, en GitHub, de donde el sistema baja paquetes, igual que lo hace
con los de Alpine. Así, cuando Lázaro mejora una herramienta o agrega una
nueva, tu equipo la recibe con el **aviso de actualizaciones** de
siempre. Todo lo que viene de ahí está **firmado** con la clave de
Lázaro: el sistema rechaza cualquier paquete que no tenga esa firma.

**Equipos instalados con una ISO nueva:** no tienes que hacer nada. En el
primer arranque con internet el equipo se conecta solo al repositorio.

**Equipos que ya tenían Lázaro antes de esta novedad:**
hay que conectarlo **una sola vez**:

1. Conéctate a internet.
2. Abre una **Terminal** (búscala como "Terminal" en el menú).
3. Copia esta línea entera, pégala en la terminal (clic derecho y
   **Pegar**, o Ctrl+Mayús+V) y pulsa Enter:

   ```sh
   wget -qO /tmp/lr https://github.com/Entropio1984/lazaro-linux/releases/download/repo-v3.24/lazaro-repositorio && doas sh /tmp/lr --activar
   ```

4. Escribe tu contraseña y pulsa Enter. Al terminar dice **Listo: las
   herramientas de Lázaro se actualizarán con las actualizaciones del
   sistema**. Desde ese momento el equipo tiene el **Afinador** (con sus
   ajustes recomendados ya aplicados) y las versiones nuevas de las otras
   herramientas.

Si dice que no pudo descargar, revisa la conexión y vuelve a pegar la
línea: se puede repetir sin problema.

**Con la terminal:**

```sh
doas lazaro-repositorio --sincronizar   # buscar ahora lo nuevo (lo hace solo cada día)
doas apk upgrade                        # instalarlo (lo mismo que el aviso de actualizaciones)
doas lazaro-repositorio --desactivar    # dejar de recibirlas (lo instalado se queda)
```

### Controladores: lo que le falta al hardware

Un **controlador** es lo que el sistema necesita para usar una pieza
(el wifi, la impresora, un lector de huellas). Lázaro revisa el equipo al
instalar y deja puesto lo que hace falta, así que normalmente no tienes
que hacer nada. Si después conectas algo que necesita un controlador,
aparece un **aviso** en la esquina de la pantalla.

**Paso a paso:**

1. Si aparece el aviso **"Falta algo para tu hardware"**, pulsa
   **Instalar**. Si no ves el aviso, abre el menú de aplicaciones y busca
   **Controladores**.
2. Se abre una lista con lo que le falta al equipo. Viene todo marcado;
   desmarca lo que no quieras.
3. Pulsa **Aceptar** y escribe tu contraseña. Lo que se descarga necesita
   internet.
4. Si alguno es el firmware de un wifi Intel viejo, primero aparece su
   **licencia**: léela y acéptala para poder instalarlo.
5. Cuando diga **Listo**, reinicia si la pieza todavía no funciona.

Si dice **"No falta nada"**, el equipo ya tiene todo lo que Lázaro sabe
revisar. Si una pieza sigue sin funcionar, pide ayuda con el informe de
diagnóstico (abajo).

**Con la terminal:**

```sh
lazaro-controladores --revisar               # lista lo que falta
doas lazaro-controladores --instalar-alpine  # instala lo que falta de Alpine
```

### Diagnóstico: pedir ayuda

Si algo no funciona, el diagnóstico arma un informe con los datos del
equipo para que otra persona pueda ayudarte.

**Paso a paso:**

1. Abre una terminal.
2. Escribe `lazaro-diagnostico` y pulsa Enter.
3. En el sistema instalado te pide tu contraseña; en la sesión de prueba
   no.
4. Espera: normalmente tarda menos de un minuto. Al final dice
   **Listo:** y el nombre del archivo.
5. El archivo queda en tu **carpeta personal** y se llama
   `lazaro-diagnostico-` con la fecha y la hora, por ejemplo
   `lazaro-diagnostico-20261103-142530.txt`. Ábrelo con doble clic si
   quieres ver qué tiene.
6. En la sesión de prueba esa carpeta se borra al apagar: copia el
   archivo a otro USB o envíalo antes.

**Qué trae:** primero, qué Lázaro tienes (versión, edición y el
**sello de compilación**: la fecha y el código exacto con que se armó tu
ISO, para saber si un arreglo ya te llegó); después, los datos del equipo y del procesador, la memoria y los
discos, el hardware (incluido lo que dice el afinador y lo que le falta
según Controladores), la red, el sonido, la pantalla y los errores del
arranque y de la instalación. No guarda contraseñas y solo tú puedes
leerlo.

**Para avisar de un problema**, abre un reporte en
[Issues](https://github.com/Entropio1984/lazaro-linux/issues) (necesitas
una cuenta de GitHub, que es gratis), cuenta qué pasa y adjunta el
informe. **Los reportes son públicos**: el informe trae datos de la red
(como las direcciones IP y los nombres de las redes guardadas) y
registros del sistema. Ábrelo antes con un editor de texto y borra lo que
no quieras mostrar.

## Palabras que aparecen en esta guía

| Palabra | Qué es |
|---|---|
| **ISO** | El archivo que contiene todo el sistema, listo para grabar en un USB |
| **Sesión de prueba (live)** | Lázaro funcionando desde el USB, sin instalar nada |
| **BIOS / UEFI** | El programa que trae el equipo para encender. BIOS es el antiguo, UEFI el moderno; Lázaro funciona con los dos |
| **Escritorio** | El aspecto del sistema: la barra, el menú y las ventanas |
| **Terminal** | Una ventana donde se escriben órdenes con el teclado |
| **doas** | Se escribe delante de una orden para ejecutarla como administrador; pide tu contraseña |
| **Flatpak / Flathub** | Una forma de instalar programas, y la tienda gratuita donde están |
| **Firmware** | Pequeños programas que necesitan algunas piezas, como el wifi, para funcionar |
| **Alpine Linux** | El sistema liviano sobre el que está hecho Lázaro |
| **Kernel (núcleo)** | La parte central del sistema, la que habla con el hardware |
| **Controlador** | Lo que el sistema necesita para usar una pieza del equipo, como el wifi o la impresora |
| **Memoria (RAM)** | Donde el equipo guarda lo que está usando en ese momento; se borra al apagar |
| **zram** | Memoria comprimida: hace que la RAM rinda más, a cambio de un poco de procesador |
| **GRUB** | El menú que aparece al encender y arranca el sistema |

---

# Para quienes quieren colaborar

Esta parte es técnica: explica cómo está hecha la ISO, cómo compilarla y
cómo se prueba.

Lázaro es una ISO de Alpine Linux con sesión live (XFCE) e instalador
gráfico Calamares. Al instalar, se elige uno de los escritorios que
Alpine soporta oficialmente con `setup-desktop` y, al final, se ejecuta
`desktop-postinstall.sh` sin hacer preguntas. Ese script vive en su
propio repositorio,
[alpine-desktop-setup](https://github.com/Entropio1984/alpine-desktop-setup),
y se descarga al compilar la ISO. Las dos ediciones se compilan,
prueban y publican solas en cada cambio de la rama principal.

## Cómo está armada

| Pieza | Dónde | Qué hace |
|---|---|---|
| Versión de Alpine y de Calamares | `config.env` | Un solo lugar para cambiar de versión |
| Origen de `desktop-postinstall.sh` | `config.env` (`POSTINSTALL_URL`) | Se descarga en cada compilación |
| Calamares | `paquetes/calamares/APKBUILD` | Alpine no lo empaqueta, así que se compila |
| Perfil de la ISO | `perfil/mkimg.lazaro.sh` | Lo usa `mkimage.sh` de aports |
| Sesión live | `perfil/genapkovl-lazaro.sh` + `live/` | Usuario `lazaro`, inicio automático, Calamares |
| Revisión de tarjetas gráficas | `live/usr/sbin/lazaro-graficas` | Decide si cargar nouveau antes del escritorio |
| Afinador | `live/usr/sbin/lazaro-afinador` | Perfil del hardware (fijo y extraíble, nivel x86-64, discos, memoria) y ajustes reversibles: `preempt=full`, Multi-Gen LRU con `min_ttl_ms`, tope de escritura en `sysctl.d`, páginas gigantes y `schedutil`; servicio de arranque y menú "Afinador" |
| Kernel Lázaro | `kernel/` + `live/usr/sbin/lazaro-kernel` | `linux-lazaro`: el linux-lts de Alpine con `kernel/lazaro.fragment` (sin hardware de servidor ni depuración, expropiación completa). Se compila, prueba en QEMU y publica en el repositorio de Lázaro cada vez que Alpine saca un linux-lts nuevo. `lazaro-kernel` lo instala junto al de Alpine y hace un arranque de prueba (`grub-reboot`) que se confirma al terminar de encender |
| Repositorio de Lázaro | `repo/`, `paquetes/lazaro-herramientas/` + `live/usr/sbin/lazaro-repositorio` | `.github/workflows/lazaro-repositorio.yml` arma el paquete `lazaro-herramientas` en cada cambio de main (y el kernel cuando toca), los firma y los publica en la Release `repo-vX.Y`. Como una Release no tiene carpetas, `lazaro-repositorio` la copia cada día a `/var/lib/lazaro-repositorio` y apk la usa como repositorio local `@lazaro` (el kernel solo se baja si está instalado) |
| Controladores que faltan | `live/usr/sbin/lazaro-controladores` | Revisa el hardware e instala lo que le falta (al instalar, al arrancar, con aviso en la sesión y desde el menú) |
| Recomendación según el equipo | `live/usr/sbin/lazaro-recomendar` | Escritorio y programas preseleccionados en Calamares según memoria, gráfica y disco |
| Pasos de instalación | `live/usr/sbin/lazaro-instalar` | Usa `setup-disk` y `setup-desktop` de Alpine |
| Pantallas del instalador | `live/etc/calamares/modules/` | Escritorio, oficina, aplicaciones, disco, usuario |
| Pantalla de arranque | `live/usr/share/plymouth/themes/lazaro/` | El logo con el pulso (Plymouth) |
| Pruebas | `pruebas/qemu.sh` | Arranque live e instalación en QEMU, BIOS y UEFI |
| Comprobaciones dentro del sistema de prueba | `live/usr/share/lazaro/pruebas/` | Solo las usa la instalación desatendida |
| Compilación automática | `.github/workflows/lazaro-iso.yml` | Estable en cada cambio; edge solo los lunes y a mano |
| Versiones numeradas | `.github/workflows/lazaro-version.yml` + `ISO_VERSION` en `config.env` | Ver [Sacar una versión](#sacar-una-versión) |
| Sello de compilación | `build.sh` → `/usr/share/lazaro/version.env` | Versión, edición, canal (`en-desarrollo`, `versión`, `prueba` o `local`), fecha, commit de la ISO y del script; lo muestra `lazaro-diagnostico` |

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
7. `lazaro-afinador --aplicar --raiz`: los ajustes recomendados para el
   hardware (bloque con marcas en `/etc/default/grub`,
   `/etc/sysctl.d/60-lazaro-afinador.conf` y el servicio
   `lazaro-afinador`, que aplica lo de `/sys` en cada arranque).

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
(QEMU) con la versión estable de Alpine. Los lunes, y al lanzarla a
mano, también con la siguiente (edge):

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
equipos con distinta memoria, gráfica y disco. Y las reglas de
`lazaro-controladores` (impresoras, huellas, wifi viejo, firmware que
falta) las recorre `pruebas/controladores.sh` con equipos simulados; en
las instalaciones de QEMU, además, se simulan un lector de huellas y uno
de tarjetas para comprobar que se instalan desde el USB. El afinador
tiene su propia prueba, `pruebas/afinador.sh`, con un portátil viejo, un
equipo nuevo y uno sin escritorio simulados (qué ajustes elige y que
aplicar y deshacer dejen GRUB como estaba); en las instalaciones de QEMU
se comprueba además que el sistema arranca con `preempt=full` y con la
protección de memoria puesta.

### Repositorio de Lázaro: compilar y publicar

```sh
./kernel/compilar.sh       # kernel; en cualquier Linux con Docker; resultado en salida/kernel/
./repo/herramientas.sh     # paquete lazaro-herramientas; resultado en salida/herramientas/
./repo/indexar.sh CARPETA  # junta paquetes viejos y nuevos y firma el índice
```

Sin la variable `LAZARO_APK_KEY` se firma con una clave de prueba (sirve
para probar, no para publicar). En GitHub, la clave es el secreto
`LAZARO_APK_KEY`, y su mitad pública es `repo/lazaro.rsa.pub` (también va
escrita dentro de `lazaro-repositorio`, y `pruebas/kernel.sh` revisa que
sean iguales); la compilación se niega a firmar si no coinciden. Solo se
publica lo firmado con la clave oficial, y solo desde main. Un paquete ya
publicado nunca se reemplaza por otro con el mismo nombre: cada cambio de
main lleva un número de versión nuevo (`git rev-list --count HEAD`).

Si cambias las herramientas, no hace falta tocar nada más: el workflow
arma el paquete solo. Si un programa nuevo debe llegar a los equipos,
agrégalo en `repo/herramientas.sh` (y en `lazaro-instalar` para las
instalaciones nuevas). Para cambiar la configuración, edita `kernel/lazaro.fragment` y
sube `KERNEL_REV` en `kernel/version`. La prueba `pruebas/kernel.sh`
recorre el repositorio (al instalar, en un equipo viejo, sin internet y
al desactivarlo) y, del kernel, la instalación, el arranque de prueba (bien y mal), una
actualización y la vuelta al kernel de Alpine; `pruebas/kernel-arranque.sh`
arranca el kernel compilado en QEMU y lo compara con el de Alpine.

## Sacar una versión

Cada cambio en main se publica solo como **en-desarrollo** (se reemplaza
cada vez). Una **versión numerada** (0.2, 0.3... y 1.0 cuando esté lista
para cualquiera) es una foto fija de una compilación que ya funcionó en
equipos reales: tiene su propia Release en GitHub, que no se borra, y su
carpeta `Versiones/X.Y` en SourceForge con las dos ediciones.

1. Revisa que `ISO_VERSION` en `config.env` sea el número que quieres
   sacar y que la última compilación de main esté en verde.
2. En GitHub: pestaña **Actions** → **Sacar una versión** → **Run
   workflow** (rama main).
3. El flujo revisa que esa versión no exista y que ese main haya pasado
   las pruebas, crea la etiqueta `vX.Y` y lanza la compilación. En unas
   2 horas la versión aparece en
   [Releases](https://github.com/Entropio1984/lazaro-linux/releases), con
   la lista de cambios (los títulos de los PR) desde la versión anterior.
4. Después, en un PR, sube `ISO_VERSION` a la siguiente versión.

Los números: se sube el último (0.2 → 0.3) con cada versión, y se pasa a
1.0 cuando Lázaro esté listo para cualquiera. Al cambiar de versión de
Alpine conviene sacar una versión nueva.

## Versiones probadas

| Alpine | Calamares | Estado |
|---|---|---|
| v3.24 | 3.4.3 | Se prueba en QEMU con las pruebas de la tabla de arriba |
| edge | 3.4.3 | Las mismas pruebas, los lunes y a mano, como aviso temprano (no bloquean) |

## Pendiente

- Cifrado de disco (desactivado por ahora).

## Licencia

Lázaro Linux es software libre: puedes usarlo, estudiarlo, compartirlo y
modificarlo según los términos de la
[Licencia Pública General de GNU, versión 3 o posterior](LICENSE)
(GPL-3.0-or-later), la misma que usa Calamares. Si redistribuyes una
versión modificada, debes compartir también su código con la misma
licencia.

Los programas que la ISO incluye o descarga (Alpine Linux, Calamares, el
firmware, los escritorios y las aplicaciones) conservan cada uno su
propia licencia.
