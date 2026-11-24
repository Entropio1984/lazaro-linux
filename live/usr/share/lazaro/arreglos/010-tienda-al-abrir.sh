#!/bin/sh
# Titulo: La lista de programas de la tienda se renueva cada vez que abres la tienda
#
# Hasta ahora la lista de programas de la tienda solo se renovaba con la
# tarea de cada hora (una vez al día). Pedido de Julián (23 de noviembre
# de 2026): renovarla cada vez que se abre la tienda, sin que la tienda
# se quede colgada y sin necesitar internet. Copia de
# setup_tienda_al_abrir de desktop-postinstall.sh desde esa fecha (allí
# se explica cómo funciona). Si allá se cambia, hace falta un arreglo
# nuevo: este ya corrió en los equipos.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"

# Sin tienda o sin la tarea de su lista (001-tienda) no hay nada que
# hacer hoy; se vuelve a mirar más adelante.
[ -x "$R/usr/bin/plasma-discover" ] || [ -x "$R/usr/bin/gnome-software" ] || exit 11
[ -x "$R/etc/periodic/hourly/alpine-tienda-catalogo" ] || exit 11
if [ -x "$R/usr/local/sbin/alpine-tienda-lista-ahora" ] &&
	[ -e "$R/etc/polkit-1/rules.d/50-alpine-tienda-lista.rules" ]; then
	hecho=si
	for t in plasma-discover gnome-software; do
		[ -x "$R/usr/bin/$t" ] || continue
		grep -q alpine-tienda-abrir "$R/usr/local/bin/$t" 2>/dev/null || hecho=no
	done
	if [ -f "$R/usr/share/applications/org.gnome.Software.desktop" ] &&
		[ ! -f "$R/usr/local/share/applications/org.gnome.Software.desktop" ]; then
		hecho=no
	fi
	[ "$hecho" = no ] || exit 10
fi

mkdir -p "$R/usr/local/sbin" "$R/usr/local/libexec" "$R/usr/local/bin" \
	"$R/usr/share/polkit-1/actions" "$R/etc/polkit-1/rules.d" || exit 1

# Cada archivo a uno aparte y después a su lugar: con el disco lleno, el
# arreglo queda pendiente en vez de dejar algo a medias.
poner() { # DESTINO MODO (el contenido llega por la entrada)
	cat > "$R$1.nuevo" && chmod "$2" "$R$1.nuevo" && mv -f "$R$1.nuevo" "$R$1" ||
		{ rm -f "$R$1.nuevo"; return 1; }
}

poner /usr/local/sbin/alpine-tienda-lista-ahora 755 <<'INNEREOF' || exit 1
#!/bin/sh
# Generado por desktop-postinstall.sh: renueva ya la lista de programas de
# la tienda. Lo llama alpine-tienda-abrir (como root, con pkexec, sin
# contrasena) cada vez que se abre la tienda. No acepta opciones.
tarea=/etc/periodic/hourly/alpine-tienda-catalogo
marca=/var/lib/swcatalog/.ultima-descarga
[ -x "$tarea" ] || exit 0
# Renovada hace menos de 30 minutos: ya esta al dia.
[ -n "$(find "$marca" -mmin -30 2>/dev/null)" ] && exit 0
# Una sola descarga a la vez (abrir la tienda dos veces no baja dos); la
# tarea de cada hora usa el mismo candado.
exec 9>/run/alpine-tienda-lista.lock || exit 0
if command -v flock >/dev/null 2>&1; then
    flock -n 9 || exit 0
fi
# Sin internet no hay nada que esperar (las lineas pueden empezar con
# una etiqueta "@nombre").
# Basta con que responda uno (20 segundos como mucho cada uno).
_red=no
for _repo in $(sed -n 's/^\(@[^[:space:]]*[[:space:]]*\)\{0,1\}\(https\{0,1\}:\/\/[^[:space:]]*\).*/\2/p' /etc/apk/repositories 2>/dev/null); do
    if timeout 20 wget -q --spider -T 8 "$_repo/$(apk --print-arch)/APKINDEX.tar.gz" 2>/dev/null; then
        _red=si
        break
    fi
done
[ "$_red" = si ] || exit 0
# La tarea solo descarga si su marca tiene mas de un dia: se aparta y,
# si esta vez no llega la lista, se devuelve (la tarea de cada hora
# sigue igual que antes).
[ ! -e "$marca" ] || mv -f "$marca" "$marca.antes"
ALPINE_TIENDA_CANDADO=ya "$tarea" || true
if [ -e "$marca" ]; then
    rm -f "$marca.antes"
elif [ -e "$marca.antes" ]; then
    mv -f "$marca.antes" "$marca"
fi
exit 0
INNEREOF
poner /usr/share/polkit-1/actions/org.alpinelinux.tienda-lista.policy 644 <<'INNEREOF' || exit 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<!-- Generado por desktop-postinstall.sh: renovar la lista de la tienda
     al abrirla, sin contrasena (solo baja la lista de programas). -->
<policyconfig>
  <action id="org.alpinelinux.tienda-lista">
    <description>Renovar la lista de programas de la tienda</description>
    <message>Renovar la lista de programas de la tienda</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/sbin/alpine-tienda-lista-ahora</annotate>
  </action>
</policyconfig>
INNEREOF
poner /etc/polkit-1/rules.d/50-alpine-tienda-lista.rules 644 <<'INNEREOF' || exit 1
// Generado por desktop-postinstall.sh: renovar la lista de la tienda.
polkit.addRule(function(action, subject) {
    if (action.id == "org.alpinelinux.tienda-lista" &&
        (subject.isInGroup("wheel") || (subject.local && subject.active))) {
        return polkit.Result.YES;
    }
});
INNEREOF
poner /usr/local/libexec/alpine-tienda-abrir 755 <<'INNEREOF' || exit 1
#!/bin/sh
# Generado por desktop-postinstall.sh: abre la tienda (el programa que se
# le pasa) y pide renovar su lista de programas. Uso:
#   alpine-tienda-abrir /usr/bin/plasma-discover [opciones de la tienda]
real="$1"
shift
# GNOME Software tambien corre escondido desde el inicio de sesion: eso no
# es abrir la tienda.
case " $* " in
    *" --gapplication-service "*) exec "$real" "$@" ;;
esac
if command -v pkexec >/dev/null 2>&1 && [ -x /usr/local/sbin/alpine-tienda-lista-ahora ]; then
    # Entre parentesis: pkexec pasa a ser root y "kill -0" no podria
    # mirarlo; el subproceso que lo espera sigue siendo de la persona.
    ( pkexec /usr/local/sbin/alpine-tienda-lista-ahora </dev/null >/dev/null 2>&1 ) &
    _pid=$!
    # Sin ninguna lista la tienda se abriria vacia: si se esta bajando
    # (sin internet termina en segundos), se avisa y se espera un poco.
    if [ -z "$(ls -A /var/lib/swcatalog/xml 2>/dev/null)" ] && command -v zenity >/dev/null 2>&1; then
        sleep 3
        if kill -0 "$_pid" 2>/dev/null; then
            case "${LANG:-}" in
                es*) _t="Tienda de aplicaciones"; _m="Descargando la lista de programas de la tienda (solo la primera vez, puede tardar unos minutos)..."; _a="Abrir ya" ;;
                pt*) _t="Loja de aplicativos"; _m="Baixando a lista de programas da loja (só na primeira vez, pode levar alguns minutos)..."; _a="Abrir agora" ;;
                *) _t="Software store"; _m="Downloading the list of programs for the store (only the first time, it may take a few minutes)..."; _a="Open now" ;;
            esac
            _n=0
            while [ "$_n" -lt 180 ] && kill -0 "$_pid" 2>/dev/null; do
                echo "#$_m" || break
                sleep 1
                _n=$((_n + 1))
            done | zenity --progress --pulsate --auto-close --width=420 \
                --title="$_t" --text="$_m" --cancel-label="$_a" >/dev/null 2>&1 || true
        fi
    fi
fi
exec "$real" "$@"
INNEREOF

for t in plasma-discover gnome-software; do
	[ -x "$R/usr/bin/$t" ] || continue
	printf '#!/bin/sh\n# Generado por desktop-postinstall.sh: renueva la lista de la tienda al abrirla.\nexec /usr/local/libexec/alpine-tienda-abrir /usr/bin/%s "$@"\n' "$t" |
		poner "/usr/local/bin/$t" 755 || exit 1
done
if [ -f "$R/usr/share/applications/org.gnome.Software.desktop" ]; then
	mkdir -p "$R/usr/local/share/applications" || exit 1
	sed '/^DBusActivatable=/d' "$R/usr/share/applications/org.gnome.Software.desktop" |
		poner /usr/local/share/applications/org.gnome.Software.desktop 644 || exit 1
fi
exit 0
