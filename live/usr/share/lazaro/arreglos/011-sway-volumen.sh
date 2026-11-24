#!/bin/sh
# Titulo: Sway: el icono de volumen abre una barrita con deslizador en vez del mezclador completo
#
# En Sway, el clic en el icono de volumen de la barra abría pavucontrol
# entero (Julián, 24 de noviembre de 2026). Copia de
# sway_instalar_volumen de desktop-postinstall.sh desde esa fecha:
# /usr/local/bin/sway-volumen, su regla en
# /etc/sway/config.d/50-lazaro-barra.conf y, en las barras que siguen
# como las dejó Lázaro, clic = barrita y clic derecho = pavucontrol.
# Una barra que la persona cambió a su gusto no se toca.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
instalado() { grep -qx "P:$1" "$R/lib/apk/db/installed" 2>/dev/null; }

# Sin Sway con waybar no hace falta; si se instala después, se vuelve a
# mirar.
{ instalado sway && instalado waybar; } || exit 11

hizo=""
faltan=""
for p in pulseaudio-utils python3 py3-gobject3 gtk+3.0; do
	instalado "$p" || faltan="$faltan $p"
done
if [ -n "$faltan" ]; then
	# shellcheck disable=SC2086
	apk add -q $faltan || exit 1
	hizo=si
fi

nuevo="$(mktemp)" || exit 1
cat > "$nuevo" <<'SWAYVOL' || { rm -f "$nuevo"; exit 1; }
#!/usr/bin/env python3
# Generado por desktop-postinstall.sh: barrita de volumen de Sway (clic en
# el icono de volumen de waybar). Se cierra al hacer clic fuera, con Esc o
# con otro clic en el icono. Clic derecho en el icono: mezclador completo.
import os
import re
import subprocess
import sys
import time

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import GLib, Gdk, Gtk  # noqa: E402

IDIOMA = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES")
          or os.environ.get("LANG") or "es")[:2]
TEXTOS = {
    "es": ("Silenciar", "Mezclador de volumen"),
    "pt": ("Silenciar", "Mixer de volume"),
    "en": ("Mute", "Volume mixer"),
}
T_SILENCIAR, T_MEZCLADOR = TEXTOS.get(IDIOMA, TEXTOS["en"])
ENTORNO = dict(os.environ, LC_ALL="C")
CARPETA = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
PID = os.path.join(CARPETA, f"sway-volumen-{os.getuid()}.pid")
CERRADA = os.path.join(CARPETA, f"sway-volumen-{os.getuid()}.cerrada")


def pactl(*args):
    try:
        return subprocess.run(["pactl", *args], capture_output=True, text=True,
                              env=ENTORNO, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def abierta():
    """Si ya hay una barrita abierta, la cierra y avisa (otro clic = cerrar)."""
    try:
        with open(PID) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"sway-volumen" not in f.read():
                return False
        os.kill(pid, 15)
        return True
    except (OSError, ValueError):
        return False


def recien_cerrada():
    # El clic en el icono primero quita el foco a la barrita (que se
    # cierra) y después llega aquí: ese clic era para cerrarla.
    try:
        return time.time() - os.path.getmtime(CERRADA) < 0.5
    except OSError:
        return False


class Barrita:
    def __init__(self):
        m = re.search(r"(\d+)%", pactl("get-sink-volume", "@DEFAULT_SINK@"))
        self.vol = int(m.group(1)) if m else 50
        self.mudo = "yes" in pactl("get-sink-mute", "@DEFAULT_SINK@")
        self.cerrada = False
        v = Gtk.Window(title="Volumen")
        v.set_decorated(False)
        v.set_resizable(False)
        caja = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        caja.set_border_width(10)
        self.boton_mudo = Gtk.Button.new_from_icon_name(self.icono(), Gtk.IconSize.BUTTON)
        self.boton_mudo.set_relief(Gtk.ReliefStyle.NONE)
        self.boton_mudo.set_tooltip_text(T_SILENCIAR)
        self.boton_mudo.connect("clicked", self.silenciar)
        self.escala = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.escala.set_draw_value(False)
        self.escala.set_size_request(200, -1)
        self.escala.set_value(min(self.vol, 100))
        self.escala.connect("value-changed", self.mover)
        self.etiqueta = Gtk.Label(label=f"{self.vol} %")
        self.etiqueta.set_width_chars(5)
        mezcla = Gtk.Button.new_from_icon_name("multimedia-volume-control", Gtk.IconSize.BUTTON)
        mezcla.set_relief(Gtk.ReliefStyle.NONE)
        mezcla.set_tooltip_text(T_MEZCLADOR)
        mezcla.connect("clicked", self.mezclador)
        for w in (self.boton_mudo, self.escala, self.etiqueta, mezcla):
            caja.pack_start(w, w is self.escala, True, 0)
        v.add(caja)
        # Se cierra al hacer clic fuera, pero no en el primer instante
        # (Sway puede tardar un momento en darle el foco).
        self.desde = time.time()
        v.connect("focus-out-event", self.foco_fuera)
        v.connect("key-press-event",
                  lambda _w, e: e.keyval == Gdk.KEY_Escape and self.cerrar())
        v.connect("destroy", lambda *_: self.cerrar())
        v.show_all()
        v.present()
        self.ventana = v

    def icono(self):
        return "audio-volume-muted" if self.mudo else "audio-volume-high"

    def mover(self, escala):
        self.vol = int(escala.get_value())
        if self.mudo:
            pactl("set-sink-mute", "@DEFAULT_SINK@", "0")
            self.mudo = False
            self.boton_mudo.set_image(Gtk.Image.new_from_icon_name(self.icono(), Gtk.IconSize.BUTTON))
        pactl("set-sink-volume", "@DEFAULT_SINK@", f"{self.vol}%")
        self.etiqueta.set_text(f"{self.vol} %")

    def silenciar(self, *_):
        pactl("set-sink-mute", "@DEFAULT_SINK@", "toggle")
        self.mudo = not self.mudo
        self.boton_mudo.set_image(Gtk.Image.new_from_icon_name(self.icono(), Gtk.IconSize.BUTTON))

    def mezclador(self, *_):
        try:
            subprocess.Popen(["pavucontrol"], start_new_session=True)
        except OSError:
            pass
        self.cerrar()

    def foco_fuera(self, *_):
        if time.time() - self.desde > 0.3:
            self.cerrar()
        return False

    def cerrar(self):
        if self.cerrada:
            return False
        self.cerrada = True
        try:
            with open(CERRADA, "w"):
                pass
        except OSError:
            pass
        try:
            os.remove(PID)
        except OSError:
            pass
        Gtk.main_quit()
        return False


if __name__ == "__main__":
    if abierta() or recien_cerrada():
        sys.exit(0)
    GLib.set_prgname("sway-volumen")
    try:
        with open(PID, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, lambda: Gtk.main_quit() or False)
    Barrita()
    Gtk.main()
SWAYVOL
if cmp -s "$nuevo" "$R/usr/local/bin/sway-volumen"; then
	rm -f "$nuevo"
else
	mkdir -p "$R/usr/local/bin" && chmod 755 "$nuevo" && mv -f "$nuevo" "$R/usr/local/bin/sway-volumen" ||
		{ rm -f "$nuevo"; exit 1; }
	hizo=si
fi

# La barrita flota bajo el puntero.
conf="$R/etc/sway/config.d/50-lazaro-barra.conf"
if [ -f "$conf" ] && [ ! -L "$conf" ] && ! grep -q 'app_id="sway-volumen"' "$conf"; then
	{
		echo "# Barrita de volumen (clic en el icono de volumen): flotando, bajo el puntero."
		echo 'for_window [app_id="sway-volumen"] floating enable, sticky enable, move position cursor, move down 45 px'
	} >> "$conf" || exit 1
	hizo=si
fi

# Barras de waybar tal como las dejó Lázaro (la de usuarios nuevos y la
# de cada persona): el clic del volumen pasa a la barrita.
for base in "$R/etc/skel" $(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home\// { print $6 }' "$R/etc/passwd" 2>/dev/null); do
	case "$base" in /home/*) base="$R$base" ;; esac
	wb="$base/.config/waybar/config.jsonc"
	# Un enlace o una barra cambiada por la persona no se tocan.
	[ -f "$wb" ] && [ ! -L "$wb" ] && [ ! -L "$base/.config/waybar" ] && [ ! -L "$base/.config" ] || continue
	grep -q '"custom/atajos"' "$wb" || continue
	grep -qx '        "on-click": "pavucontrol"' "$wb" || continue
	t="$(mktemp "$wb.XXXXXX")" || exit 1
	sed 's/^        "on-click": "pavucontrol"$/        "on-click": "sway-volumen || pavucontrol",\
        "on-click-right": "pavucontrol"/' "$wb" > "$t" || { rm -f "$t"; exit 1; }
	chmod 644 "$t"
	case "$base" in
		*/etc/skel) ;;
		*) chown "$(stat -c %u:%g "$wb")" "$t" 2>/dev/null || true ;;
	esac
	mv -f "$t" "$wb" || { rm -f "$t"; exit 1; }
	hizo=si
done

[ -n "$hizo" ] || exit 10
exit 0
