# Imágenes del README

- `pulso.gif`: la animación de arranque (tema Plymouth de `live/usr/share/plymouth/themes/lazaro/`).
- `bienvenida-claro.png` y `bienvenida-oscuro.png`: la Bienvenida con un tema claro y uno oscuro.
- `flathub.png`: la ventana "Aplicaciones de Flathub" (`lazaro-flatpak --ventana`), donde se instala Google Chrome. Es una copia de la captura `flathub` del manual (flujo "Capturas del manual").
- `nubes.png`: la ventana del botón "Lázaro Nubes" (`lazaro-nubes --ventana`) antes de instalar. Es una copia de la captura `nubes` del manual (flujo "Capturas del manual").
- `sway-claudito.png`: Sway con la barra Claudito Shell Fusion, una terminal y Mousepad. Es una copia de la captura `sway-claudito` del manual. Esta y `sway-claudito-menu`/`sway-claudito-atajos` NO las renueva el flujo "Capturas del manual" (ese recorre XFCE): se sacaron una vez con Sway sin pantalla (`WLR_BACKENDS=headless`, `grim`) en un contenedor Alpine con los paquetes `quickshell` y `lazaro-claudito`. Para renovarlas, reemplázalas a mano.

La captura grande de la Bienvenida que sale arriba en el README no está
aquí: es `manual/imagenes/capturas/bienvenida.png`, la misma del manual,
y se renueva sola cada vez que corre el flujo "Capturas del manual".
Para cambiar una de estas, reemplaza el archivo con el mismo nombre.
