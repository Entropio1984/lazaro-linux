# Tema Lázaro

El aspecto de Lázaro para los escritorios de 64 bits (XFCE, MATE, LXQt,
Plasma, GNOME y Sway). Todo lo que hay bajo `usr/` va tal cual al
sistema, con las mismas rutas: a la sesión de prueba (lo copia
`perfil/genapkovl-lazaro.sh`), al disco al instalar (`paso_tema` de
`lazaro-instalar`) y a los equipos ya instalados con el paquete
`lazaro-herramientas` (`repo/herramientas.sh`).

Colores (los del logo): azul noche `#0a1f36`, celeste del pulso
`#29b6f6`, azul de los detalles `#1a7fd0` y amarillo del sol `#f6c344`.

## Las piezas

| Pieza | Archivos | Se elige en |
|---|---|---|
| Fondos | `usr/share/backgrounds/lazaro/*.jpg`; listas para GNOME y MATE (`gnome-background-properties/`, `mate-background-properties/`) y paquetes para Plasma (`wallpapers/Lazaro-*`) | La ventana de fondos de cada escritorio |
| Colores de las ventanas (GTK 3) | `usr/share/themes/Lazaro` (claro) y `Lazaro-Oscuro`: toman la forma de `adw-gtk3` (paquete de Alpine) y cambian solo los colores; `colores-lazaro.css` tiene lo común y el color de las barras de XFCE y MATE | Apariencia (XFCE, MATE, LXQt) |
| Barra de título de XFCE | `usr/share/themes/Lazaro/xfwm4` (PNG dibujados por `generar-imagenes.py`) | Gestor de ventanas |
| Barra de título de MATE | `usr/share/themes/Lazaro/metacity-1/metacity-theme-1.xml` | Apariencia > Tema |
| Barra de título de LXQt | `usr/share/themes/Lazaro/openbox-3/themerc` | Configuración de Openbox |
| Íconos | `usr/share/icons/Lazaro`: hereda Papirus (o los del escritorio si Papirus no está) y cambia el botón del menú por el pulso. El dibujo chico (16 a 24 px) es aparte porque el grande, achicado, parecía una cruz | Apariencia > Íconos |
| Barra de LXQt y colores de Qt | `usr/share/lxqt/themes/Lazaro`, `usr/share/lxqt/palettes/Lazaro*` | Apariencia de LXQt |
| Plasma | `usr/share/plasma/look-and-feel/org.lazaro.{claro,oscuro}.desktop` (tema global: colores, íconos y fondo) y `usr/share/color-schemes/Lazaro*.colors` | Preferencias del sistema > Tema global |

`lazaro-tema` (en `live/usr/sbin`) pone todo junto con un clic según el
escritorio, guarda cómo estaba antes y lo devuelve al quitarlo. Lo usa el
botón "Aspecto del escritorio" de la Bienvenida, y al entrar por primera
vez a un equipo recién instalado (`/etc/lazaro/tema-de-entrada`).

## Cambiar los dibujos

Los fondos, el ícono del menú, los botones de las ventanas de XFCE y las
vistas previas de Plasma los dibuja un programa, así que se pueden
retocar y volver a generar sin programas de dibujo:

    python3 tema/generar-imagenes.py

(necesita Pillow). Da siempre el mismo resultado: si no se cambió el
programa, git no ve cambios. Para un fondo nuevo: agregar su función en
`generar-imagenes.py`, sumarlo a las dos listas de fondos (GNOME y MATE)
y crear su carpeta en `usr/share/wallpapers/` como las que ya están.

Al terminar: `sh pruebas/tema.sh`.
