#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Motor de sincronización de Nubes Rclone (Python puro, sin GLib ni GTK).

Mantiene al día las carpetas locales configuradas con su nube (rclone bisync):
cada pocos minutos y unos segundos después de que cambie algo en la carpeta.

- El icono del área de notificaciones (nubes_bandeja.py) lo usa como parte
  visual: le pasa sus propias funciones para notificar y redibujar el menú, y
  vigila los cambios con inotify.
- Si no hay PyGObject (sistemas mínimos, servidores, gestores de ventanas sin
  bandeja), este archivo funciona solo:  nubes-rclone --sincronizar-servicio
  Detecta los cambios revisando la carpeta periódicamente y avisa con
  notify-send si está disponible.
"""

import fcntl
import hashlib
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time

DIR_APP = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, DIR_APP)
import nubes_rclone as nr  # noqa: E402

MAX_RECIENTES = 30
ESPERA_TRAS_CAMBIO = 15       # segundos sin cambios antes de subir lo modificado
SONDEO_CAMBIOS = 20           # sin inotify: cada cuánto se revisa la carpeta local


def acortar(texto, n=48):
    return texto if len(texto) <= n else texto[:n // 2 - 1] + "…" + texto[-(n // 2 - 1):]


def firma_carpeta(carpeta):
    """Huella barata del contenido (rutas, tamaños y fechas) para detectar cambios."""
    h = hashlib.sha1()
    for raiz, dirs, archivos in os.walk(carpeta):
        dirs.sort()
        for a in sorted(archivos):
            if nr.ignorar_archivo(a):
                continue
            ruta = os.path.join(raiz, a)
            try:
                st = os.stat(ruta)
            except OSError:
                continue
            h.update(("%s\0%d\0%d\n" % (ruta, st.st_size, int(st.st_mtime))).encode("utf-8", "replace"))
    return h.hexdigest()


class Motor:
    """Planificación y ejecución de las sincronizaciones.

    Funciones que da quien lo usa (todas opcionales):
      llamar(f, *args)         ejecutar f en el hilo principal (por defecto, una cola)
      notificar(titulo, cuerpo, icono, accion=None, texto_accion="Abrir")
      al_cambiar()             redibujar el icono/menú
      vigilar(nombre) / dejar_de_vigilar(nombre)   vigilancia con inotify
      otra_peticion(accion, nombre)                peticiones que no son de sincronización
    Si no se da `vigilar`, el motor revisa las carpetas cada SONDEO_CAMBIOS segundos.
    """

    def __init__(self, llamar=None, notificar=None, al_cambiar=None, vigilar=None,
                 dejar_de_vigilar=None, otra_peticion=None):
        self.cola = queue.Queue()
        self.llamar = llamar or (lambda f, *a: self.cola.put((f, a)))
        self.notificar = notificar or (lambda *a, **k: None)
        self.al_cambiar = al_cambiar or (lambda: None)
        self._vigilar = vigilar
        self._dejar_de_vigilar = dejar_de_vigilar or (lambda nombre: None)
        self.otra_peticion = otra_peticion or (lambda accion, nombre: None)

        self.ajustes = nr.cargar_ajustes()
        self.mtime_ajustes = self._mtime()
        previo = nr.leer_estado()
        self.nubes = {}            # nombre -> estado de su sincronización
        for nombre, st in previo.get("nubes", {}).items():
            self.nubes[nombre] = {"estado": "pendiente" if st.get("estado") == "sincronizando"
                                  else st.get("estado", "pendiente"),
                                  "ultima": st.get("ultima", 0), "ultimo_intento": 0,
                                  "mensaje": st.get("mensaje", "")}
        self.recientes = previo.get("recientes", [])[:MAX_RECIENTES]
        self.hay_nuevos = bool(previo.get("hay_nuevos"))
        self.procesos = {}         # nombre -> Popen en curso
        self.en_curso = set()
        self.cancelados = set()
        self.instantaneas = {}
        self.cambios_locales = {}
        self.firmas = {}           # sondeo sin inotify: nombre -> (momento, huella)
        self.remotos = {}
        self.t_remotos = 0
        self.mtime_rclone = None
        self.version = nr.version_tupla()
        self.firma_estado = None
        self.leer_remotos()

    def iniciar_vigilancia(self):
        """Empieza a vigilar las carpetas (se llama cuando quien usa el motor ya está listo)."""
        for nombre in self.sincs():
            self.vigilar(nombre)

    # --------------------------- ajustes ---------------------------
    def _mtime(self):
        try:
            return os.path.getmtime(nr.ARCHIVO_AJUSTES)
        except OSError:
            return 0

    def sincs(self):
        return self.ajustes.get("sincronizacion", {})

    def carpeta(self, nombre):
        conf = self.sincs().get(nombre) or {}
        return os.path.expanduser(conf.get("carpeta") or nr.carpeta_sinc_defecto(nombre))

    def modificar_ajustes(self, funcion):
        """Relee, modifica y guarda bajo el bloqueo compartido con la ventana."""
        self.ajustes = nr.modificar_ajustes(funcion)
        self.mtime_ajustes = self._mtime()

    def recargar_ajustes(self):
        m = self._mtime()
        if m == self.mtime_ajustes:
            return
        antes = {n: dict(c) for n, c in self.sincs().items()}
        self.ajustes = nr.cargar_ajustes()
        self.mtime_ajustes = m
        ahora = self.sincs()
        for nombre in set(antes) | set(ahora):
            if nombre not in ahora:                       # sincronización desactivada
                self.dejar_de_vigilar(nombre)
                self.nubes.pop(nombre, None)
                self.instantaneas.pop(nombre, None)
            elif nombre not in antes or antes[nombre].get("carpeta") != ahora[nombre].get("carpeta"):
                self.instantaneas.pop(nombre, None)       # nueva o carpeta cambiada
                self.nubes.setdefault(nombre, {})["ultimo_intento"] = 0
                self.vigilar(nombre)
        self.t_remotos = 0

    def leer_remotos(self):
        self.remotos = dict(nr.listar_remotos())
        self.t_remotos = time.time()
        self.mtime_rclone = self._mtime_rclone()

    @staticmethod
    def _mtime_rclone():
        ruta = os.environ.get("RCLONE_CONFIG") or os.path.join(nr.XDG_CONFIG, "rclone", "rclone.conf")
        try:
            return os.path.getmtime(ruta)
        except OSError:
            return 0

    # ------------------- vigilancia de cambios locales -------------------
    def vigilar(self, nombre):
        if self._vigilar:
            self._vigilar(nombre)
        else:
            self.firmas.pop(nombre, None)

    def dejar_de_vigilar(self, nombre):
        self._dejar_de_vigilar(nombre)
        self.firmas.pop(nombre, None)

    def cambio_local(self, nombre):
        """Algo cambió en la carpeta local (lo avisa inotify o el sondeo)."""
        if nombre not in self.en_curso:
            self.cambios_locales[nombre] = time.time()

    def _sondear(self, ahora):
        if self._vigilar:
            return                                         # ya hay inotify
        for nombre in self.sincs():
            if nombre in self.en_curso:
                continue
            momento, huella = self.firmas.get(nombre, (0, None))
            if ahora - momento < SONDEO_CAMBIOS:
                continue
            carpeta = self.carpeta(nombre)
            if not os.path.isdir(carpeta):
                continue
            nueva = firma_carpeta(carpeta)
            if huella is not None and nueva != huella:
                self.cambio_local(nombre)
            self.firmas[nombre] = (ahora, nueva)

    # --------------------------- ciclo ---------------------------
    def tick(self):
        """Se llama cada pocos segundos desde el bucle de quien usa el motor."""
        try:
            self.atender_peticiones()
            self.recargar_ajustes()
            ahora = time.time()
            # Releer las conexiones si cambió rclone.conf (nube conectada o eliminada,
            # también desde la terminal) o, como mucho, cada minuto
            if ahora - self.t_remotos > 60 or self._mtime_rclone() != self.mtime_rclone:
                self.leer_remotos()
            self._sondear(ahora)
            if not self.ajustes.get("pausado"):
                for nombre, conf in self.sincs().items():
                    if nombre in self.en_curso or nombre not in self.remotos:
                        continue
                    st = self.nubes.setdefault(nombre, {"estado": "pendiente", "ultima": 0,
                                                        "ultimo_intento": 0, "mensaje": ""})
                    intervalo = max(1, int(conf.get("intervalo", 5))) * 60
                    if st.get("estado") == "error":
                        intervalo = min(intervalo, 180)   # reintentar antes tras un fallo
                    vencido = ahora - st.get("ultimo_intento", 0) >= intervalo
                    cambio = self.cambios_locales.get(nombre)
                    if vencido or (cambio and ahora - cambio >= ESPERA_TRAS_CAMBIO):
                        self.lanzar(nombre)
            self.al_cambiar()
            self.publicar_estado()
        except Exception as e:  # noqa: BLE001 - el motor no debe morir por un error puntual
            print("Error en el ciclo:", repr(e), file=sys.stderr)
        return True

    def atender_peticiones(self):
        try:
            peticiones = os.listdir(nr.DIR_PETICIONES)
        except OSError:
            return
        for archivo in peticiones:
            try:
                os.remove(os.path.join(nr.DIR_PETICIONES, archivo))
            except OSError:
                continue
            accion, _, nombre = archivo.partition("--")
            self.recargar_ajustes()
            if nombre and nombre not in self.remotos:
                self.leer_remotos()          # puede ser una nube recién conectada
            # Solo se aceptan nombres de conexiones que existen de verdad
            if nombre and (not nr.nombre_valido(nombre) or nombre not in self.remotos):
                print("Petición ignorada (nube desconocida):", archivo, file=sys.stderr)
                continue
            if accion == "sincronizar" and nombre:
                self.sincronizar(nombre)
            elif accion == "reparar" and nombre:
                self.sincronizar(nombre, resync=True)
            elif accion == "sincronizar-todo":
                self.sincronizar_todo()
            elif accion == "pausar":
                self.poner_pausa(True)
            elif accion == "reanudar":
                self.poner_pausa(False)
            else:
                self.otra_peticion(accion, nombre)

    # ------------------------ sincronización ------------------------
    def sincronizar(self, nombre, resync=False):
        if nombre in self.sincs() and nombre not in self.en_curso:
            if self.ajustes.get("pausado"):
                self.notificar("Sincronización en pausa",
                               "Reanuda la sincronización para continuar.", "nubes-rclone-pausa")
                return
            self.lanzar(nombre, resync)

    def sincronizar_todo(self):
        for nombre in self.sincs():
            self.sincronizar(nombre)
        return False

    def lanzar(self, nombre, resync=False):
        conf = self.sincs()[nombre]
        carpeta = self.carpeta(nombre)
        tipo = self.remotos.get(nombre, "")
        inicial = resync or not conf.get("inicializada")
        st = self.nubes.setdefault(nombre, {"ultima": 0})
        st.update(estado="sincronizando", ultimo_intento=time.time(), mensaje="")
        self.cambios_locales.pop(nombre, None)
        self.en_curso.add(nombre)
        bwlimit = self.ajustes.get("bwlimit") or None
        threading.Thread(target=self._trabajo, args=(nombre, tipo, carpeta, inicial, bwlimit),
                         daemon=True).start()
        self.al_cambiar()

    def _ejecutar(self, nombre, orden):
        log = os.path.join(nr.asegurar_dir(nr.DIR_LOGS), nombre + "-sincronizacion.log")
        try:
            if os.path.getsize(log) > 2 * 1024 * 1024:
                os.replace(log, log + ".1")
        except OSError:
            pass
        try:
            proc = subprocess.Popen(orden, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors="replace")
        except OSError as e:
            return 127, str(e)
        self.procesos[nombre] = proc
        salida, _ = proc.communicate()
        self.procesos.pop(nombre, None)
        try:
            with open(log, "a", encoding="utf-8") as f:
                f.write("\n==== %s  %s ====\n%s" % (time.strftime("%F %T"), " ".join(orden[1:6]), salida))
        except OSError:
            pass
        return proc.returncode, salida

    def _trabajo(self, nombre, tipo, carpeta, inicial, bwlimit):
        try:
            os.makedirs(carpeta, exist_ok=True)
            previa = self.instantaneas.get(nombre)
            antes = nr.instantanea(carpeta)
            subidos = sorted(antes - previa) if previa is not None and not inicial else []
            codigo, salida = self._ejecutar(nombre, nr.orden_bisync(
                nombre, tipo, carpeta, inicial, self.version, bwlimit))
            reparado = False
            if (codigo != 0 and not inicial and nombre not in self.cancelados
                    and nr.necesita_resync(salida)):
                # bisync perdió su historial (o una carpeta estaba vacía): volver a unir
                # ambas copias. --resync nunca borra archivos.
                codigo, salida = self._ejecutar(nombre, nr.orden_bisync(
                    nombre, tipo, carpeta, True, self.version, bwlimit))
                reparado = True
            despues = nr.instantanea(carpeta)
            descargados = sorted(despues - antes)
        except Exception as e:  # noqa: BLE001
            codigo, salida, subidos, descargados, despues, reparado = 1, str(e), [], [], None, False
        # Sin inotify: la referencia para detectar cambios se toma justo al terminar,
        # para no pasar por alto lo que se cree en los segundos siguientes
        huella = None
        if not self._vigilar and os.path.isdir(carpeta):
            huella = (time.time(), firma_carpeta(carpeta))
        self.llamar(self._fin, nombre, carpeta, codigo, salida, subidos, descargados,
                    inicial, reparado, despues, huella)

    def _fin(self, nombre, carpeta, codigo, salida, subidos, descargados, inicial, reparado,
             despues, huella=None):
        self.en_curso.discard(nombre)
        st = self.nubes.setdefault(nombre, {})
        estado_previo = st.get("estado")
        if nombre in self.cancelados:
            self.cancelados.discard(nombre)
            st.update(estado="pendiente", mensaje="Detenida al pausar.")
        elif codigo == 0:
            st.update(estado="ok", ultima=time.time(), mensaje="")
            if despues is not None:
                self.instantaneas[nombre] = despues
            if inicial and nombre in self.sincs() and not self.sincs()[nombre].get("inicializada"):
                self.modificar_ajustes(
                    lambda a: a["sincronizacion"].get(nombre, {}).update(inicializada=True))
            if inicial and not reparado:
                total = len(despues or [])
                self.notificar("«%s» está lista" % nombre,
                               "Primera sincronización completada: %d archivo(s) en %s" % (total, carpeta),
                               "nubes-rclone-ok", lambda: nr.abrir_en_explorador(carpeta), "Abrir carpeta")
            else:
                self._registrar(nombre, carpeta, descargados, subidos)
        else:
            st.update(estado="error", mensaje=nr.interpretar_error(salida))
            if estado_previo != "error":
                self.notificar("Problema al sincronizar «%s»" % nombre, st["mensaje"],
                               "nubes-rclone-error")
        self.vigilar(nombre)
        if huella:
            self.firmas[nombre] = huella
        self.al_cambiar()
        self.publicar_estado()
        return False

    def _registrar(self, nombre, carpeta, descargados, subidos):
        ahora = time.time()
        nuevos = ([{"t": ahora, "nube": nombre, "ruta": r, "dir": "↓"} for r in descargados] +
                  [{"t": ahora, "nube": nombre, "ruta": r, "dir": "↑"} for r in subidos])
        if not nuevos:
            return
        self.recientes = (nuevos + self.recientes)[:MAX_RECIENTES]
        if descargados:
            self.hay_nuevos = True
            lista = "\n".join("• " + acortar(r, 60) for r in descargados[:5])
            if len(descargados) > 5:
                lista += "\n… y %d más" % (len(descargados) - 5)
            if len(descargados) == 1:
                destino = os.path.join(carpeta, descargados[0])
                accion, texto = (lambda: nr.abrir_en_explorador(destino)), "Abrir archivo"
            else:
                accion, texto = (lambda: nr.abrir_en_explorador(carpeta)), "Abrir carpeta"
            self.notificar("%d archivo(s) nuevo(s) en «%s»" % (len(descargados), nombre), lista,
                           "nubes-rclone-nuevo", accion, texto)

    def poner_pausa(self, pausar):
        self.modificar_ajustes(lambda a: a.update(pausado=pausar))
        if pausar:
            self.detener_procesos(signal.SIGINT)     # rclone se detiene de forma ordenada
        else:
            for st in self.nubes.values():
                st["ultimo_intento"] = 0              # sincronizar en el siguiente ciclo
        self.al_cambiar()

    def detener_procesos(self, senal=signal.SIGINT, esperar=0):
        for nombre, proc in list(self.procesos.items()):
            self.cancelados.add(nombre)
            try:
                proc.send_signal(senal)
                if esperar:
                    proc.wait(timeout=esperar)
            except (OSError, subprocess.TimeoutExpired):
                proc.kill()

    def olvidar_recientes(self):
        self.recientes = []
        self.hay_nuevos = False

    # ----------------------------- estado -----------------------------
    def publicar_estado(self):
        estado = {
            "pid": os.getpid(),
            "pausado": bool(self.ajustes.get("pausado")),
            "hay_nuevos": self.hay_nuevos,
            "nubes": {n: {"estado": "sincronizando" if n in self.en_curso else st.get("estado", "pendiente"),
                          "ultima": st.get("ultima", 0), "mensaje": st.get("mensaje", "")}
                      for n, st in self.nubes.items()},
            "recientes": self.recientes,
        }
        if estado != self.firma_estado:
            self.firma_estado = estado
            try:
                nr.escribir_estado(estado)
            except OSError:
                pass

    def atender_cola(self):
        """Ejecuta en el hilo principal lo que terminaron los hilos de trabajo."""
        while True:
            try:
                f, args = self.cola.get_nowait()
            except queue.Empty:
                return
            f(*args)


# ==========================================================================
#  Servicio sin interfaz (cuando no hay PyGObject o se pide expresamente)
# ==========================================================================

def notificar_consola(titulo, cuerpo, icono="nubes-rclone", accion=None, texto_accion=None):
    print("[%s] %s: %s" % (time.strftime("%H:%M:%S"), titulo, cuerpo.replace("\n", " ")))
    if shutil.which("notify-send") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        try:
            subprocess.Popen(["notify-send", "-a", nr.APP_NOMBRE, "-i", icono, titulo, cuerpo],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        except OSError:
            pass


def main():
    nr.asegurar_dir(nr.DIR_LOGS)
    nr.asegurar_dir(nr.DIR_EJEC)
    nr.asegurar_dir(nr.DIR_PETICIONES)
    # Mismo bloqueo que el icono: nunca hay dos motores a la vez
    bloqueo = open(nr.ARCHIVO_BLOQUEO_BANDEJA, "a")
    try:
        fcntl.flock(bloqueo, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("La sincronización de Nubes Rclone ya está en marcha.")
        return 0
    if not nr.rclone_bin():
        print("ERROR: rclone no está instalado.", file=sys.stderr)
        return 1
    # Una petición «salir» que quedó de antes (cuando no había nada en marcha) no debe
    # cerrar esta instancia nada más arrancar
    try:
        os.remove(os.path.join(nr.DIR_PETICIONES, "salir"))
    except OSError:
        pass
    problemas = nr.limpiar_sesion_si_hace_falta()   # modo compartido: una vez por sesión
    if problemas:
        notificar_consola("NO se pudieron desconectar todas las nubes",
                          "Siguen accesibles: " + ", ".join(problemas), "nubes-rclone-error")

    seguir = [True]

    def otra(accion, _nombre):
        if accion == "salir":
            seguir[0] = False
    motor = Motor(notificar=notificar_consola, otra_peticion=otra)
    motor.iniciar_vigilancia()

    def parar(*_):
        seguir[0] = False
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, parar)
    print("Sincronización de Nubes Rclone en marcha (sin icono). Ctrl+C para detener.")
    ultimo = 0
    while seguir[0]:
        motor.atender_cola()
        if time.time() - ultimo >= 5:
            motor.tick()
            ultimo = time.time()
        time.sleep(0.5)
    motor.detener_procesos(signal.SIGINT, esperar=20)
    motor.atender_cola()
    print("Sincronización detenida.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
