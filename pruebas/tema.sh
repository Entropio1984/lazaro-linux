#!/bin/sh
# Prueba el tema Lázaro sin escritorio de verdad:
#   - los archivos del tema están completos y bien escritos (GTK, íconos,
#     ventanas de XFCE, MATE y Openbox, Plasma, LXQt, fondos);
#   - lazaro-tema pone el tema en cada escritorio con programas falsos
#     (xfconf-query, gsettings, plasma-apply-*, kreadconfig6, swaymsg) y
#     al quitarlo deja todo como estaba;
#   - --primera-vez lo pone una sola vez y solo si el equipo empieza con
#     el tema.
#
#   pruebas/tema.sh

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$DIR/live/usr/sbin/lazaro-tema"
T="$DIR/tema/usr/share"
TMP="$(mktemp -d)"
[ -d "$TMP" ] || exit 1
trap 'rm -rf "$TMP"' EXIT

fallos=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
mal() { n=$((n + 1)); fallos=$((fallos + 1)); echo "FALLO $n $1" >&2; }
es() { if eval "$2"; then ok "$1"; else mal "$1"; fi; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else mal "$1: salió [$2], se esperaba [$3]"; fi; }

# --- Archivos del tema ------------------------------------------------------
for f in lazaro-fondo lazaro-pulso lazaro-amanecer lazaro-claro; do
	es "fondo $f.jpg" "[ -s '$T/backgrounds/lazaro/$f.jpg' ]"
done
for v in Lazaro Lazaro-Oscuro; do
	es "GTK $v: index.theme" "grep -q '^GtkTheme=$v$' '$T/themes/$v/index.theme'"
	es "GTK $v: se apoya en adw-gtk3" "grep -q '@import url(\"../../adw-gtk3' '$T/themes/$v/gtk-3.0/gtk.css'"
done
es "colores comunes" "[ -s '$T/themes/Lazaro/gtk-3.0/colores-lazaro.css' ]"
es "íconos: hereda Papirus" "grep -q '^Inherits=Papirus,' '$T/icons/Lazaro/index.theme'"
for i in start-here distributor-logo org.xfce.panel.applicationsmenu start-here-kde lxqt-mainmenu; do
	es "ícono del menú: $i" "[ -e '$T/icons/Lazaro/scalable/apps/$i.svg' ] && [ -e '$T/icons/Lazaro/16x16/apps/$i.svg' ]"
done
# Cada carpeta de íconos tiene que estar en Directories y al revés.
for d in $(sed -n 's/^Directories=//p' "$T/icons/Lazaro/index.theme" | tr ',' ' '); do
	es "íconos: existe $d" "[ -d '$T/icons/Lazaro/$d' ] && grep -q '^\[$d\]' '$T/icons/Lazaro/index.theme'"
done
rotos="$(find "$DIR/tema" -type l | while read -r l; do [ -e "$l" ] || echo "$l"; done)"
igual "enlaces sin romper" "$rotos" ""
for b in close hide maximize maximize-toggled menu shade stick; do
	for e in active inactive prelight pressed; do
		[ -s "$T/themes/Lazaro/xfwm4/$b-$e.png" ] || mal "xfwm4: falta $b-$e.png"
	done
done
ok "xfwm4: botones completos"
es "xfwm4: themerc" "grep -q '^active_text_color=' '$T/themes/Lazaro/xfwm4/themerc'"
es "Openbox: themerc" "grep -q '^window.active.title.bg.color:' '$T/themes/Lazaro/openbox-3/themerc'"
es "LXQt: barra" "grep -q 'LXQtPanel #BackgroundWidget' '$T/lxqt/themes/Lazaro/lxqt-panel.qss'"
for v in claro oscuro; do
	es "Plasma $v: metadata" "grep -q '\"Id\": \"org.lazaro.$v.desktop\"' '$T/plasma/look-and-feel/org.lazaro.$v.desktop/metadata.json'"
	es "Plasma $v: vista previa" "[ -s '$T/plasma/look-and-feel/org.lazaro.$v.desktop/contents/previews/preview.png' ]"
	c="$(sed -n 's/^ColorScheme=//p' "$T/plasma/look-and-feel/org.lazaro.$v.desktop/contents/defaults")"
	es "Plasma $v: colores $c existen" "[ -s '$T/color-schemes/$c.colors' ]"
	w="$(sed -n 's/^Image=//p' "$T/plasma/look-and-feel/org.lazaro.$v.desktop/contents/defaults")"
	es "Plasma $v: fondo $w existe" "[ -s '$T/wallpapers/$w/metadata.json' ]"
done
if command -v python3 >/dev/null 2>&1; then
	es "JSON de Plasma" "python3 -c 'import json,sys; [json.load(open(f)) for f in sys.argv[1:]]' $(find "$T/plasma" "$T/wallpapers" -name metadata.json | tr '\n' ' ')"
	es "XML de fondos y de Marco" "python3 -c 'import sys,xml.dom.minidom as m; [m.parse(f) for f in sys.argv[1:]]' '$T/gnome-background-properties/lazaro.xml' '$T/mate-background-properties/lazaro.xml' '$T/themes/Lazaro/metacity-1/metacity-theme-1.xml'"
fi
for f in "$T"/gnome-background-properties/lazaro.xml "$T"/mate-background-properties/lazaro.xml; do
	for img in $(sed -n 's|.*<filename>/usr/share/\(.*\)</filename>.*|\1|p' "$f"); do
		es "fondo de la lista existe: $img" "[ -s '$T/$img' ]"
	done
done

# --- Programas falsos -------------------------------------------------------
B="$TMP/bin"
mkdir -p "$B"
DB="$TMP/db"
mkdir -p "$DB"
# xfconf-query y gsettings: un archivo por clave.
cat > "$B/xfconf-query" <<'EOF'
#!/bin/sh
c=""; p=""; v=""; borrar=no; listar=no
while [ $# -gt 0 ]; do
	case "$1" in
		-c) c="$2"; shift ;; -p) p="$2"; shift ;; -s) v="$2"; shift ;;
		-t) shift ;; -n) ;; -r) borrar=si ;; -l) listar=si ;;
	esac
	shift
done
f="$DB/xf_$(echo "$c$p" | tr '/' '_')"
if [ "$listar" = si ]; then ls "$DB" | sed -n "s|^xf_$c||p" | tr '_' '/'; exit 0; fi
if [ "$borrar" = si ]; then rm -f "$f"; exit 0; fi
if [ -n "$v" ]; then printf '%s' "$v" > "$f"; exit 0; fi
[ -e "$f" ] && cat "$f" && echo || exit 1
EOF
cat > "$B/gsettings" <<'EOF'
#!/bin/sh
f="$DB/gs_$2_$3"
case "$1" in
	writable) echo true ;;
	range) [ "$3" = accent-color ] && echo "enum 'blue'" || exit 1 ;;
	get) if [ -e "$f" ]; then cat "$f"; else echo "'de-fabrica'"; fi ;;
	set) printf '%s' "$4" > "$f" ;;
	reset) rm -f "$f" ;;
esac
EOF
cat > "$B/plasma-apply-lookandfeel" <<'EOF'
#!/bin/sh
echo "$2" > "$DB/plasma_laf"
EOF
cat > "$B/plasma-apply-wallpaperimage" <<'EOF'
#!/bin/sh
echo "$1" > "$DB/plasma_fondo"
EOF
cat > "$B/kreadconfig6" <<'EOF'
#!/bin/sh
cat "$DB/plasma_laf" 2>/dev/null || echo org.kde.breeze.desktop
EOF
cat > "$B/swaymsg" <<'EOF'
#!/bin/sh
echo "$*" >> "$DB/swaymsg"
EOF
for p in pgrep openbox pcmanfm-qt xrandr; do printf '#!/bin/sh\nexit 1\n' > "$B/$p"; done
chmod +x "$B"/*
export DB PATH="$B:$PATH" LAZARO_TEMA_ESPERA=0 LAZARO_TEMA_FONDOS="$T/backgrounds/lazaro" \
	LAZARO_TEMA_PALETAS="$T/lxqt/palettes" LAZARO_TEXTO_DIR="$DIR/live/usr/share/lazaro"

casa() { # NOMBRE: carpeta personal nueva
	HOME="$TMP/casa-$1"
	XDG_CONFIG_HOME="$HOME/.config"
	rm -rf "$HOME"
	mkdir -p "$HOME"
	export HOME XDG_CONFIG_HOME
	rm -f "$DB"/*
}
xfv() { cat "$DB/xf_$(echo "$1" | tr '/' '_')" 2>/dev/null || echo "(nada)"; }
gsv() { cat "$DB/gs_$1_$2" 2>/dev/null || echo "(nada)"; }

# --- XFCE -------------------------------------------------------------------
casa xfce
export XDG_CURRENT_DESKTOP=XFCE
"$B/xfconf-query" -c xsettings -p /Net/ThemeName -s Adwaita
"$B/xfconf-query" -c xfce4-desktop -p /backdrop/screen0/monitorVirtual-1/workspace0/last-image -s /usr/share/backgrounds/xfce/raton.png
igual "XFCE: estado al empezar" "$(sh "$PROG" --estado)" original
sh "$PROG" --aplicar oscuro
igual "XFCE: tema GTK oscuro" "$(xfv xsettings/Net/ThemeName)" Lazaro-Oscuro
igual "XFCE: íconos" "$(xfv xsettings/Net/IconThemeName)" Lazaro
igual "XFCE: ventanas" "$(xfv xfwm4/general/theme)" Lazaro
igual "XFCE: fondo" "$(xfv xfce4-desktop/backdrop/screen0/monitorVirtual-1/workspace0/last-image)" "$T/backgrounds/lazaro/lazaro-pulso.jpg"
igual "XFCE: estado" "$(sh "$PROG" --estado)" oscuro
sh "$PROG" --aplicar claro
igual "XFCE: de oscuro a claro" "$(xfv xsettings/Net/ThemeName)" Lazaro
sh "$PROG" --quitar
igual "XFCE: quitar devuelve el tema de antes (no el oscuro)" "$(xfv xsettings/Net/ThemeName)" Adwaita
igual "XFCE: quitar devuelve el fondo" "$(xfv xfce4-desktop/backdrop/screen0/monitorVirtual-1/workspace0/last-image)" /usr/share/backgrounds/xfce/raton.png
igual "XFCE: quitar borra lo que no había" "$(xfv xfwm4/general/theme)" "(nada)"
igual "XFCE: estado tras quitar" "$(sh "$PROG" --estado)" original

# --- GNOME, MATE y Sway -----------------------------------------------------
casa gnome
export XDG_CURRENT_DESKTOP=GNOME
sh "$PROG" --aplicar claro
igual "GNOME: tema GTK" "$(gsv org.gnome.desktop.interface gtk-theme)" Lazaro
igual "GNOME: color de detalles" "$(gsv org.gnome.desktop.interface accent-color)" blue
igual "GNOME: fondo" "$(gsv org.gnome.desktop.background picture-uri)" "file://$T/backgrounds/lazaro/lazaro-amanecer.jpg"
sh "$PROG" --quitar
igual "GNOME: quitar" "$(gsv org.gnome.desktop.interface gtk-theme)" "'de-fabrica'"

casa mate
export XDG_CURRENT_DESKTOP=MATE
sh "$PROG" --aplicar oscuro
igual "MATE: ventanas" "$(gsv org.mate.Marco.general theme)" Lazaro
igual "MATE: GTK" "$(gsv org.mate.interface gtk-theme)" Lazaro-Oscuro
igual "MATE: fondo" "$(gsv org.mate.background picture-filename)" "$T/backgrounds/lazaro/lazaro-pulso.jpg"
sh "$PROG" --quitar
igual "MATE: quitar" "$(gsv org.mate.Marco.general theme)" "'de-fabrica'"

casa sway
export XDG_CURRENT_DESKTOP=sway
sh "$PROG" --aplicar claro
es "Sway: fondo en config.d" "grep -q 'output \* bg \"$T/backgrounds/lazaro/lazaro-amanecer.jpg\" fill' '$HOME/.config/sway/config.d/90-lazaro-tema.conf'"
igual "Sway: GTK" "$(gsv org.gnome.desktop.interface gtk-theme)" Lazaro
sh "$PROG" --quitar
es "Sway: quitar borra el fondo" "[ ! -e '$HOME/.config/sway/config.d/90-lazaro-tema.conf' ]"

# --- Plasma -----------------------------------------------------------------
casa plasma
export XDG_CURRENT_DESKTOP=KDE
mkdir -p "$HOME/.config"
printf '[Containments][1][Wallpaper][org.kde.image][General]\nImage=file:///usr/share/wallpapers/Next/\n' \
	> "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
sh "$PROG" --aplicar oscuro
igual "Plasma: tema global" "$(cat "$DB/plasma_laf")" org.lazaro.oscuro.desktop
igual "Plasma: fondo" "$(cat "$DB/plasma_fondo")" "$T/backgrounds/lazaro/lazaro-pulso.jpg"
sh "$PROG" --quitar
igual "Plasma: quitar vuelve a Breeze" "$(cat "$DB/plasma_laf")" org.kde.breeze.desktop
igual "Plasma: quitar vuelve al fondo" "$(cat "$DB/plasma_fondo")" /usr/share/wallpapers/Next/

# --- LXQt -------------------------------------------------------------------
casa lxqt
export XDG_CURRENT_DESKTOP=LXQt
mkdir -p "$HOME/.config/lxqt" "$HOME/.config/openbox"
printf '[General]\ntheme=Clearlooks\nicon_theme=breeze\n\n[Qt]\nstyle=Fusion\n' > "$HOME/.config/lxqt/lxqt.conf"
printf '<openbox_config>\n<theme>\n  <name>Clearlooks</name>\n</theme>\n</openbox_config>\n' > "$HOME/.config/openbox/lxqt-rc.xml"
cp "$HOME/.config/lxqt/lxqt.conf" "$TMP/lxqt-antes"
sh "$PROG" --aplicar oscuro
es "LXQt: tema de la barra" "grep -qx 'theme=Lazaro' '$HOME/.config/lxqt/lxqt.conf'"
es "LXQt: paleta oscura" "grep -qx 'window_color=#0f2742' '$HOME/.config/lxqt/lxqt.conf'"
es "LXQt: Qt sin tocar" "grep -qx 'style=Fusion' '$HOME/.config/lxqt/lxqt.conf'"
es "LXQt: Openbox" "grep -q '<name>Lazaro</name>' '$HOME/.config/openbox/lxqt-rc.xml'"
es "LXQt: GTK" "grep -qx 'gtk-theme-name=Lazaro-Oscuro' '$HOME/.config/gtk-3.0/settings.ini'"
es "LXQt: fondo" "grep -qx 'Wallpaper=$T/backgrounds/lazaro/lazaro-pulso.jpg' '$HOME/.config/pcmanfm-qt/lxqt/settings.conf'"
sh "$PROG" --quitar
es "LXQt: quitar devuelve el tema" "grep -qx 'theme=Clearlooks' '$HOME/.config/lxqt/lxqt.conf'"
es "LXQt: quitar borra la paleta" "! grep -q 'window_color' '$HOME/.config/lxqt/lxqt.conf'"
es "LXQt: quitar devuelve Openbox" "grep -q '<name>Clearlooks</name>' '$HOME/.config/openbox/lxqt-rc.xml'"

# --- Primera vez --------------------------------------------------------------
casa primera
export XDG_CURRENT_DESKTOP=MATE LAZARO_TEMA_ENTRADA="$TMP/tema-de-entrada"
rm -f "$LAZARO_TEMA_ENTRADA"
sh "$PROG" --primera-vez
igual "primera vez: sin tema de entrada no hace nada" "$(gsv org.mate.Marco.general theme)" "(nada)"
echo claro > "$LAZARO_TEMA_ENTRADA"
sh "$PROG" --primera-vez
igual "primera vez: lo pone" "$(gsv org.mate.Marco.general theme)" Lazaro
sh "$PROG" --quitar
sh "$PROG" --primera-vez
igual "primera vez: no vuelve a ponerlo si la persona lo quitó" "$(sh "$PROG" --estado)" original

# --- Escritorio desconocido ---------------------------------------------------
casa otro
export XDG_CURRENT_DESKTOP=IceWM
rc=0; sh "$PROG" --aplicar claro 2>/dev/null || rc=$?
es "IceWM: no hace nada y avisa" "[ $rc != 0 ] && [ ! -e '$HOME/.config/lazaro/tema' ]"

echo
if [ "$fallos" -gt 0 ]; then
	echo "$fallos de $n pruebas fallaron." >&2
	exit 1
fi
echo "Las $n pruebas pasaron."
