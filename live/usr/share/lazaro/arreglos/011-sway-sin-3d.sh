#!/bin/sh
# Titulo: Sway: el menú y las ventanas ya no dejan manchas en equipos sin aceleración 3D
#
# En una máquina virtual sin 3D, el menú de Sway dejaba manchas; con el
# modo de dibujo simple de Sway (WLR_RENDERER=pixman) se ve bien (Julián,
# 24 de noviembre de 2026). Copia de sway_dibujo_sin_3d de
# desktop-postinstall.sh desde esa fecha: /usr/local/bin/sway elige el
# modo en cada arranque según el controlador de la gráfica.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
# Sin Sway no hace falta; si la persona lo instala después, se vuelve a
# mirar.
grep -qx "P:sway" "$R/lib/apk/db/installed" 2>/dev/null || exit 11

nuevo="$(mktemp)" || exit 1
cat > "$nuevo" <<'SWAY_EOF' || { rm -f "$nuevo"; exit 1; }
#!/bin/sh
# Generado por desktop-postinstall.sh: en equipos sin aceleracion 3D,
# Sway dibuja en modo simple (pixman) para evitar manchas en pantalla.
# Para forzar un modo: WLR_RENDERER=gles2 (normal) o pixman.
if [ -z "${WLR_RENDERER:-}" ]; then
    real_3d=no
    for card in /sys/class/drm/card[0-9]*; do
        case "${card##*/}" in *-*) continue ;; esac
        [ -e "$card/device/driver" ] || continue
        case "$(basename "$(readlink -f "$card/device/driver")")" in
            i915|xe|amdgpu|radeon|nouveau) real_3d=si ;;
        esac
    done
    [ "$real_3d" = si ] || export WLR_RENDERER=pixman
fi
exec /usr/bin/sway "$@"
SWAY_EOF
if cmp -s "$nuevo" "$R/usr/local/bin/sway"; then
	rm -f "$nuevo"
	exit 10
fi
mkdir -p "$R/usr/local/bin" && chmod 755 "$nuevo" && mv -f "$nuevo" "$R/usr/local/bin/sway" ||
	{ rm -f "$nuevo"; exit 1; }
exit 0
