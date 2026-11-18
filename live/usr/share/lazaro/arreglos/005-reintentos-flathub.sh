#!/bin/sh
# Titulo: OnlyOffice, Chrome y Brave: si Flathub no responde, la descarga se reintenta con más paciencia
#
# Las aplicaciones de Flathub que quedan pendientes se bajan en segundo
# plano al encender (/etc/local.d/flatpak-pendientes.start, que escribe
# desktop-postinstall.sh). Antes probaba una vez por minuto y se rendía a
# los 20 minutos; en un Acer Aspire 4739 (17 de noviembre de 2026)
# Flathub se cortaba ("Timeout was reached") y no alcanzaba. La versión
# nueva espera internet sin gastar intentos y reintenta cada vez más
# espaciado (hasta cada 30 minutos). Es copia de la que escribe
# flatpak_pendiente en desktop-postinstall.sh desde el 18 de noviembre
# de 2026: si se cambia allá, hace falta un arreglo nuevo.
#
# LAZARO_ARREGLO_RAIZ: para las pruebas, sistema de mentira.

R="${LAZARO_ARREGLO_RAIZ:-}"
LISTA="$R/etc/flatpak-pendientes"
INICIO="$R/etc/local.d/flatpak-pendientes.start"

# Sin nada pendiente no hay nada que cambiar.
[ -s "$LISTA" ] || exit 10
grep -q 'Paciente con la red' "$INICIO" 2>/dev/null && exit 10

mkdir -p "$R/etc/local.d" || exit 1
cat > "$INICIO.nuevo" <<'PEND' || exit 1
#!/bin/sh
# Generado por desktop-postinstall.sh: instala en segundo plano las
# aplicaciones de Flathub que no se pudieron instalar antes. Se borra
# sola cuando no queda ninguna pendiente.
#
# Paciente con la red: sin internet espera (sin gastar intentos); si una
# descarga se corta (Flathub a veces no responde: "Timeout was reached"),
# reintenta cada vez mas espaciado (2, 4, 8... hasta 30 minutos), hasta
# 24 veces por encendido, y sigue en el proximo encendido. Lo ya bajado
# no se vuelve a bajar.
lista=/etc/flatpak-pendientes
log=/var/log/flatpak-pendientes.log
candado=/run/flatpak-pendientes.pid
[ -s "$lista" ] || { rm -f "$0"; exit 0; }
# Una sola copia a la vez.
if [ -s "$candado" ] && kill -0 "$(cat "$candado")" 2>/dev/null; then exit 0; fi
# El paquete flatpak de Alpine crea el repositorio sin la carpeta state/:
# cada descarga avisa "Encountered error marking commit partial" (no la
# detiene, pero asusta en el registro).
[ ! -d /var/lib/flatpak/repo/objects ] || mkdir -p /var/lib/flatpak/repo/state 2>/dev/null
(
    intento=0
    espera=120
    sleep 60
    while [ -s "$lista" ] && [ "$intento" -lt 24 ]; do
        if ! wget -q --spider -T 30 https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1; then
            sleep 120
            continue
        fi
        intento=$((intento + 1))
        echo "== $(date '+%F %T') intento $intento: $(tr '\n' ' ' < "$lista")" >>"$log"
        if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$log" 2>&1; then
            for app in $(cat "$lista"); do
                if nice -n 10 flatpak install -y --noninteractive flathub "$app" >>"$log" 2>&1; then
                    echo "== $(date '+%F %T') instalada: $app" >>"$log"
                    grep -vx "$app" "$lista" > "$lista.tmp"; mv -f "$lista.tmp" "$lista"
                fi
            done
        fi
        [ -s "$lista" ] || break
        echo "== $(date '+%F %T') la conexion con Flathub fallo; se reintenta en $((espera / 60)) min" >>"$log"
        sleep "$espera"
        espera=$((espera * 2))
        [ "$espera" -le 1800 ] || espera=1800
    done
    if [ -s "$lista" ]; then
        echo "== $(date '+%F %T') quedan pendientes; se sigue en el proximo encendido con internet" >>"$log"
    else
        echo "== $(date '+%F %T') listo: todas instaladas" >>"$log"
        # Se borra solo si sigue vacia: si el script agrego otra mientras
        # tanto, la lista y este archivo se quedan para el proximo arranque.
        [ -s "$lista" ] || rm -f "$lista" /etc/local.d/flatpak-pendientes.start
    fi
    rm -f "$candado"
) >/dev/null 2>&1 &
echo $! > "$candado"
PEND
chmod 755 "$INICIO.nuevo" && mv -f "$INICIO.nuevo" "$INICIO" || exit 1
# El servicio "local" de OpenRC es el que lo corre al encender.
[ -e "$R/etc/runlevels/default/local" ] || ln -sf /etc/init.d/local "$R/etc/runlevels/default/local" 2>/dev/null || true
# Si ya hay internet, empieza ahora y no espera al próximo encendido. La
# versión vieja, si sigue corriendo, termina su vuelta y se va.
[ -n "$R" ] || sh "$INICIO" >/dev/null 2>&1 || true
exit 0
