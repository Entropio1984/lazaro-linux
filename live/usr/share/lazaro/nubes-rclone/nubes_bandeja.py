#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Icono de Lázaro Nubes en el área de notificaciones (bandeja del sistema).

- Sincroniza las carpetas locales configuradas con su nube (rclone bisync):
  cada pocos minutos y unos segundos después de que cambies algo en la carpeta.
- Muestra si está sincronizando, si hay errores o si está en pausa.
- Avisa con una notificación cuando llegan archivos nuevos desde la nube.
- Menú: abrir la carpeta local o la nube en la web, sincronizar ahora,
  pausar/reanudar, ver archivos añadidos recientemente.

Solo necesita PyGObject (Gio/GLib). El icono usa el protocolo
StatusNotifierItem (KDE Plasma, GNOME con la extensión AppIndicator, XFCE,
LXQt, Cinnamon, MATE, Budgie, Waybar...). Si el escritorio solo tiene una
bandeja X11 antigua, usa Gtk.StatusIcon como respaldo.
"""

import fcntl
import os
import signal
import subprocess
import sys
import threading
import time

DIR_APP = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, DIR_APP)
import nubes_rclone as nr  # noqa: E402
from nubes_sinc import Motor, acortar  # noqa: E402

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    Gio = GLib = None

DIR_TEMA = os.path.join(nr.XDG_DATA, "icons")
DIR_ICONOS = os.path.join(DIR_TEMA, "hicolor", "scalable", "apps")
MAX_MONITORES = 3000          # límite de carpetas vigiladas por nube (inotify)

# --------------------------------------------------------------------------
# Iconos (SVG) — se instalan en ~/.local/share/icons/hicolor/scalable/apps
# --------------------------------------------------------------------------
_NUBE = '<path d="M16 52a12 12 0 0 1-1.5-23.9A18 18 0 0 1 49.6 24 14 14 0 0 1 48 52z" fill="%s"/>'
ICONOS = {
    "nubes-rclone-ok": _NUBE % "#3b82f6" +
        '<path d="M22 39l7 7 13-14" stroke="#fff" stroke-width="5" fill="none" '
        'stroke-linecap="round" stroke-linejoin="round"/>',
    "nubes-rclone-sync": _NUBE % "#3b82f6" +
        '<g stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round">'
        '<path d="M22.5 38a10 10 0 0 1 17-7.1"/><path d="M41.5 40a10 10 0 0 1-17 7.1"/></g>'
        '<path d="M42 24.5v9h-9z" fill="#fff"/><path d="M22 53.5v-9h9z" fill="#fff"/>',
    "nubes-rclone-pausa": _NUBE % "#8a94a6" +
        '<rect x="24" y="30" width="6" height="16" rx="1.5" fill="#fff"/>'
        '<rect x="34" y="30" width="6" height="16" rx="1.5" fill="#fff"/>',
    "nubes-rclone-error": _NUBE % "#8a94a6" +
        '<circle cx="46" cy="44" r="13" fill="#dc2626" stroke="#fff" stroke-width="2"/>'
        '<rect x="44" y="35" width="4" height="11" rx="1.5" fill="#fff"/>'
        '<circle cx="46" cy="50.5" r="2.3" fill="#fff"/>',
    "nubes-rclone-nuevo": _NUBE % "#3b82f6" +
        '<path d="M32 30v16M25 39l7 7 7-7" stroke="#fff" stroke-width="5" fill="none" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
        '<circle cx="50" cy="17" r="9" fill="#f59e0b" stroke="#fff" stroke-width="2.5"/>',
    "nubes-rclone": '<rect x="4" y="14" width="56" height="42" rx="6" fill="#3b82f6"/>'
        '<path d="M4 20a6 6 0 0 1 6-6h14l5 6h25a6 6 0 0 1 6 6v0H4z" fill="#2563eb"/>'
        '<path d="M22 46h22a8 8 0 0 0 1-15.9A11 11 0 0 0 24 32a7 7 0 0 0-2 14z" fill="#fff"/>',
}


def instalar_iconos():
    os.makedirs(DIR_ICONOS, exist_ok=True)
    for nombre, cuerpo in ICONOS.items():
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">%s</svg>\n' % cuerpo
        ruta = os.path.join(DIR_ICONOS, nombre + ".svg")
        try:
            with open(ruta, encoding="utf-8") as f:
                if f.read() == svg:
                    continue
        except OSError:
            pass
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(svg)


def abrir(destino):
    """Abre una carpeta, archivo o URL con la aplicación predeterminada."""
    nr.abrir_en_explorador(destino)


# ==========================================================================
#  Notificaciones de escritorio (org.freedesktop.Notifications)
# ==========================================================================

class Notificador:
    def __init__(self, bus):
        self.bus = bus
        self.acciones = {}
        bus.signal_subscribe(None, "org.freedesktop.Notifications", "ActionInvoked",
                             "/org/freedesktop/Notifications", None,
                             Gio.DBusSignalFlags.NONE, self._accion)
        # Un aviso que se cierra sin pulsar (o que vence) ya no necesita su acción
        bus.signal_subscribe(None, "org.freedesktop.Notifications", "NotificationClosed",
                             "/org/freedesktop/Notifications", None,
                             Gio.DBusSignalFlags.NONE, self._cerrada)

    def enviar(self, titulo, cuerpo, icono="nubes-rclone", accion=None, texto_accion="Abrir"):
        acciones = ["default", texto_accion] if accion else []
        hints = {"desktop-entry": GLib.Variant("s", nr.APP_ID)}

        def respuesta(bus, res):
            try:
                nid = bus.call_finish(res).unpack()[0]
                if accion:
                    self.acciones[nid] = accion
            except GLib.Error as e:
                print("Notificación no enviada:", e.message, file=sys.stderr)

        self.bus.call("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                      "org.freedesktop.Notifications", "Notify",
                      GLib.Variant("(susssasa{sv}i)", (nr.APP_NOMBRE, 0, icono, titulo, cuerpo,
                                                        acciones, hints, 10000)),
                      GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None, respuesta)

    def _accion(self, _bus, _remitente, _ruta, _iface, _senal, parametros, *_):
        nid, _clave = parametros.unpack()
        funcion = self.acciones.pop(nid, None)
        if funcion:
            funcion()

    def _cerrada(self, _bus, _remitente, _ruta, _iface, _senal, parametros, *_):
        nid = parametros.unpack()[0]
        # ActionInvoked llega antes que NotificationClosed: si se pulsó, ya se usó
        self.acciones.pop(nid, None)


# ==========================================================================
#  Icono StatusNotifierItem + menú com.canonical.dbusmenu
# ==========================================================================

XML_SNI = """
<node>
 <interface name="org.kde.StatusNotifierItem">
  <property name="Category" type="s" access="read"/>
  <property name="Id" type="s" access="read"/>
  <property name="Title" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="WindowId" type="i" access="read"/>
  <property name="IconThemePath" type="s" access="read"/>
  <property name="IconName" type="s" access="read"/>
  <property name="IconPixmap" type="a(iiay)" access="read"/>
  <property name="OverlayIconName" type="s" access="read"/>
  <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
  <property name="AttentionIconName" type="s" access="read"/>
  <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
  <property name="AttentionMovieName" type="s" access="read"/>
  <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  <property name="ItemIsMenu" type="b" access="read"/>
  <property name="Menu" type="o" access="read"/>
  <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
  <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
  <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
  <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
  <signal name="NewTitle"/>
  <signal name="NewIcon"/>
  <signal name="NewAttentionIcon"/>
  <signal name="NewOverlayIcon"/>
  <signal name="NewToolTip"/>
  <signal name="NewStatus"><arg name="status" type="s"/></signal>
 </interface>
</node>
"""

XML_MENU = """
<node>
 <interface name="com.canonical.dbusmenu">
  <property name="Version" type="u" access="read"/>
  <property name="TextDirection" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="IconThemePath" type="as" access="read"/>
  <method name="GetLayout">
   <arg type="i" name="parentId" direction="in"/>
   <arg type="i" name="recursionDepth" direction="in"/>
   <arg type="as" name="propertyNames" direction="in"/>
   <arg type="u" name="revision" direction="out"/>
   <arg type="(ia{sv}av)" name="layout" direction="out"/>
  </method>
  <method name="GetGroupProperties">
   <arg type="ai" name="ids" direction="in"/>
   <arg type="as" name="propertyNames" direction="in"/>
   <arg type="a(ia{sv})" name="properties" direction="out"/>
  </method>
  <method name="GetProperty">
   <arg type="i" name="id" direction="in"/>
   <arg type="s" name="name" direction="in"/>
   <arg type="v" name="value" direction="out"/>
  </method>
  <method name="Event">
   <arg type="i" name="id" direction="in"/>
   <arg type="s" name="eventId" direction="in"/>
   <arg type="v" name="data" direction="in"/>
   <arg type="u" name="timestamp" direction="in"/>
  </method>
  <method name="EventGroup">
   <arg type="a(isvu)" name="events" direction="in"/>
   <arg type="ai" name="idErrors" direction="out"/>
  </method>
  <method name="AboutToShow">
   <arg type="i" name="id" direction="in"/>
   <arg type="b" name="needUpdate" direction="out"/>
  </method>
  <method name="AboutToShowGroup">
   <arg type="ai" name="ids" direction="in"/>
   <arg type="ai" name="updatesNeeded" direction="out"/>
   <arg type="ai" name="idErrors" direction="out"/>
  </method>
  <signal name="ItemsPropertiesUpdated">
   <arg type="a(ia{sv})" name="updatedProps"/>
   <arg type="a(ias)" name="removedProps"/>
  </signal>
  <signal name="LayoutUpdated">
   <arg type="u" name="revision"/>
   <arg type="i" name="parent"/>
  </signal>
  <signal name="ItemActivationRequested">
   <arg type="i" name="id"/>
   <arg type="u" name="timestamp"/>
  </signal>
 </interface>
</node>
"""


class IconoSNI:
    RUTA_ITEM = "/StatusNotifierItem"
    RUTA_MENU = "/MenuBar"
    IFACE_ITEM = "org.kde.StatusNotifierItem"
    IFACE_MENU = "com.canonical.dbusmenu"

    def __init__(self, bus, bandeja):
        self.bus = bus
        self.bandeja = bandeja
        self.revision = 1
        self.items = {0: {"_ids": []}}
        self.items_previos = {}
        self.ids = {}
        self.siguiente_id = 1
        self.icono = "nubes-rclone-ok"
        self.titulo_tip = nr.APP_NOMBRE
        self.texto_tip = ""
        self.registrado = False
        self.nombre_bus = "org.kde.StatusNotifierItem-%d-1" % os.getpid()

        info_item = Gio.DBusNodeInfo.new_for_xml(XML_SNI).interfaces[0]
        info_menu = Gio.DBusNodeInfo.new_for_xml(XML_MENU).interfaces[0]
        bus.register_object(self.RUTA_ITEM, info_item, self._metodo_item, self._propiedad_item, None)
        bus.register_object(self.RUTA_MENU, info_menu, self._metodo_menu, self._propiedad_menu, None)
        bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                      "RequestName", GLib.Variant("(su)", (self.nombre_bus, 4)), None,
                      Gio.DBusCallFlags.NONE, -1, None)
        # Registrarse cada vez que aparezca el «vigilante» (p. ej. si se reinicia el panel)
        Gio.bus_watch_name_on_connection(bus, "org.kde.StatusNotifierWatcher",
                                         Gio.BusNameWatcherFlags.NONE,
                                         self._vigilante_aparece, self._vigilante_desaparece)

    # ---------------------------- registro ----------------------------
    def _vigilante_aparece(self, bus, _nombre, _dueno):
        try:
            bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                          "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                          GLib.Variant("(s)", (self.nombre_bus,)), None,
                          Gio.DBusCallFlags.NONE, -1, None)
            self.registrado = True
            self.bandeja.icono_registrado()
        except GLib.Error as e:
            print("No se pudo registrar el icono:", e.message, file=sys.stderr)

    def _vigilante_desaparece(self, *_):
        self.registrado = False

    # ------------------------- API para la bandeja -------------------------
    def poner_icono(self, icono, titulo, texto):
        if icono != self.icono:
            self.icono = icono
            self._senal(self.RUTA_ITEM, self.IFACE_ITEM, "NewIcon")
        if (titulo, texto) != (self.titulo_tip, self.texto_tip):
            self.titulo_tip, self.texto_tip = titulo, texto
            self._senal(self.RUTA_ITEM, self.IFACE_ITEM, "NewToolTip")

    def poner_menu(self, modelo):
        # Cada elemento conserva su número mientras siga en el mismo sitio con el
        # mismo texto, y un número nunca se reutiliza para otro elemento. Si se
        # renumerara todo en cada cambio, el panel (libdbusmenu-qt) mezclaría
        # elementos viejos y nuevos y mostraría entradas duplicadas.
        self.items_previos = self.items
        self.items = {0: {"_ids": []}}
        ids_nuevos = {}

        def asignar(lista, padre, ruta):
            for pos, it in enumerate(lista):
                clave = ruta + "/" + ("—sep%d" % pos if it.get("sep") else it.get("texto", ""))
                i = self.ids.get(clave)
                if i is None or i in self.items:
                    i = self.siguiente_id
                    self.siguiente_id += 1
                ids_nuevos[clave] = i
                self.items[i] = it
                padre["_ids"].append(i)
                if it.get("hijos"):
                    it["_ids"] = []
                    asignar(it["hijos"], it, clave)
        asignar(modelo, self.items[0], "")
        self.ids = ids_nuevos
        self.revision += 1
        self._senal(self.RUTA_MENU, self.IFACE_MENU, "LayoutUpdated",
                    GLib.Variant("(ui)", (self.revision, 0)))

    def _senal(self, ruta, iface, nombre, params=None):
        try:
            self.bus.emit_signal(None, ruta, iface, nombre, params)
        except GLib.Error:
            pass

    # ------------------------- StatusNotifierItem -------------------------
    def _propiedad_item(self, _con, _rem, _ruta, _iface, prop):
        vacio = GLib.Variant("a(iiay)", [])
        valores = {
            "Category": GLib.Variant("s", "ApplicationStatus"),
            "Id": GLib.Variant("s", nr.APP_ID),
            "Title": GLib.Variant("s", nr.APP_NOMBRE),
            "Status": GLib.Variant("s", "Active"),
            "WindowId": GLib.Variant("i", 0),
            "IconThemePath": GLib.Variant("s", DIR_TEMA),
            "IconName": GLib.Variant("s", self.icono),
            "IconPixmap": vacio,
            "OverlayIconName": GLib.Variant("s", ""),
            "OverlayIconPixmap": vacio,
            "AttentionIconName": GLib.Variant("s", ""),
            "AttentionIconPixmap": vacio,
            "AttentionMovieName": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", (self.icono, [], self.titulo_tip, self.texto_tip)),
            "ItemIsMenu": GLib.Variant("b", False),
            "Menu": GLib.Variant("o", self.RUTA_MENU),
        }
        return valores.get(prop)

    def _metodo_item(self, _con, _rem, _ruta, _iface, metodo, _params, invocacion):
        if metodo == "Activate":
            GLib.idle_add(self.bandeja.alternar_ventana)
        elif metodo == "SecondaryActivate":
            GLib.idle_add(self.bandeja.sincronizar_todo)
        invocacion.return_value(None)

    # ---------------------------- dbusmenu ----------------------------
    def _propiedad_menu(self, _con, _rem, _ruta, _iface, prop):
        return {
            "Version": GLib.Variant("u", 3),
            "TextDirection": GLib.Variant("s", "ltr"),
            "Status": GLib.Variant("s", "normal"),
            "IconThemePath": GLib.Variant("as", [DIR_TEMA]),
        }.get(prop)

    def _props(self, ident):
        it = self.items.get(ident, {})
        if ident == 0:
            return {"children-display": GLib.Variant("s", "submenu")}
        if it.get("sep"):
            return {"type": GLib.Variant("s", "separator")}
        p = {"label": GLib.Variant("s", it.get("texto", "").replace("_", "__"))}
        if not it.get("activo", True):
            p["enabled"] = GLib.Variant("b", False)
        if it.get("marcado") is not None:
            p["toggle-type"] = GLib.Variant("s", "checkmark")
            p["toggle-state"] = GLib.Variant("i", 1 if it["marcado"] else 0)
        if it.get("_ids"):
            p["children-display"] = GLib.Variant("s", "submenu")
        if it.get("icono"):
            p["icon-name"] = GLib.Variant("s", it["icono"])
        return p

    def _arbol(self, ident, profundidad):
        hijos = []
        if profundidad != 0:
            for h in self.items.get(ident, {}).get("_ids", []):
                hijos.append(GLib.Variant("(ia{sv}av)", self._arbol(h, profundidad - 1)))
        return (ident, self._props(ident), hijos)

    def _evento(self, ident, tipo):
        if tipo == "clicked":
            # El menú pudo cambiar justo mientras estaba abierto: buscar también en el anterior
            accion = (self.items.get(ident) or self.items_previos.get(ident) or {}).get("accion")
            if accion:
                GLib.idle_add(lambda: (accion(), False)[1])

    def _metodo_menu(self, _con, _rem, _ruta, _iface, metodo, params, invocacion):
        args = params.unpack()
        if metodo == "GetLayout":
            padre, prof, _nombres = args
            if padre not in self.items:
                padre = 0
            invocacion.return_value(GLib.Variant("(u(ia{sv}av))",
                                                 (self.revision, self._arbol(padre, prof))))
        elif metodo == "GetGroupProperties":
            ids = args[0] or list(self.items)
            invocacion.return_value(GLib.Variant(
                "(a(ia{sv}))", ([(i, self._props(i)) for i in ids if i in self.items],)))
        elif metodo == "GetProperty":
            valor = self._props(args[0]).get(args[1], GLib.Variant("s", ""))
            invocacion.return_value(GLib.Variant("(v)", (valor,)))
        elif metodo == "Event":
            self._evento(args[0], args[1])
            invocacion.return_value(None)
        elif metodo == "EventGroup":
            for ident, tipo, _datos, _ts in args[0]:
                self._evento(ident, tipo)
            invocacion.return_value(GLib.Variant("(ai)", ([],)))
        elif metodo == "AboutToShow":
            if args[0] == 0:
                GLib.idle_add(self.bandeja.menu_abierto)
            invocacion.return_value(GLib.Variant("(b)", (False,)))
        elif metodo == "AboutToShowGroup":
            if 0 in args[0]:
                GLib.idle_add(self.bandeja.menu_abierto)
            invocacion.return_value(GLib.Variant("(aiai)", ([], [])))
        else:
            invocacion.return_value(None)


# ==========================================================================
#  Respaldo para bandejas X11 antiguas (Gtk.StatusIcon / XEmbed)
# ==========================================================================

class IconoGtk:
    def __init__(self, bandeja):
        os.environ.setdefault("GDK_BACKEND", "x11")
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        self.Gtk = Gtk
        self.bandeja = bandeja
        self.modelo = []
        Gtk.IconTheme.get_default().append_search_path(DIR_TEMA)
        self.icono = Gtk.StatusIcon.new_from_icon_name("nubes-rclone-ok")
        self.icono.set_title(nr.APP_NOMBRE)
        self.icono.connect("activate", lambda *_: bandeja.alternar_ventana())
        self.icono.connect("popup-menu", self._menu)

    def visible(self, si):
        self.icono.set_visible(si)

    def poner_icono(self, icono, titulo, texto):
        self.icono.set_from_icon_name(icono)
        self.icono.set_tooltip_text(titulo + "\n" + texto)

    def poner_menu(self, modelo):
        self.modelo = modelo

    def _construir(self, modelo):
        Gtk = self.Gtk
        menu = Gtk.Menu()
        for it in modelo:
            if it.get("sep"):
                elemento = Gtk.SeparatorMenuItem()
            elif it.get("marcado") is not None:
                elemento = Gtk.CheckMenuItem(label=it["texto"])
                elemento.set_active(it["marcado"])
            else:
                elemento = Gtk.MenuItem(label=it["texto"])
            elemento.set_sensitive(it.get("activo", True))
            if it.get("hijos"):
                elemento.set_submenu(self._construir(it["hijos"]))
            elif it.get("accion"):
                accion = it["accion"]
                elemento.connect("activate", lambda *_a, f=accion: f())
            menu.append(elemento)
        menu.show_all()
        return menu

    def _menu(self, icono, boton, momento):
        self.bandeja.menu_abierto()
        self.menu_gtk = self._construir(self.modelo)
        self.menu_gtk.popup(None, None, self.Gtk.StatusIcon.position_menu, icono, boton, momento)


# ==========================================================================
#  Lógica de la bandeja: planificación de sincronizaciones y menú
# ==========================================================================

class Bandeja:
    """Parte visual: icono, menú y notificaciones. La sincronización la hace el
    motor (nubes_sinc.Motor), que también funciona solo si no hay PyGObject."""

    def __init__(self, bucle):
        self.bucle = bucle
        self.monitores = {}
        self.firma_menu = None
        self.aviso_sin_bandeja = False
        self.ultimo_lanzamiento = -10.0
        self.ultimo_clic = -10.0
        self.sni = self.gtk = None

        instalar_iconos()
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.notificador = Notificador(self.bus)
        self.motor = Motor(
            llamar=lambda f, *a: GLib.idle_add(f, *a),
            notificar=self.notificador.enviar,
            al_cambiar=self.actualizar,
            vigilar=self.vigilar,
            dejar_de_vigilar=self.dejar_de_vigilar,
            otra_peticion=self._otra_peticion)
        self.motor.iniciar_vigilancia()
        if self.ajustes.get("equipo_compartido"):
            self.olvidar_cuentas(al_iniciar=True)     # una vez por inicio de sesión
        self.sni = IconoSNI(self.bus, self)
        self.actualizar()
        GLib.timeout_add_seconds(8, self._comprobar_bandeja)
        GLib.timeout_add_seconds(5, self.motor.tick)

    # ------------- acceso al estado del motor (usado por el menú) -------------
    ajustes = property(lambda self: self.motor.ajustes)
    nubes = property(lambda self: self.motor.nubes)
    en_curso = property(lambda self: self.motor.en_curso)
    remotos = property(lambda self: self.motor.remotos)
    recientes = property(lambda self: self.motor.recientes)

    @property
    def hay_nuevos(self):
        return self.motor.hay_nuevos

    @hay_nuevos.setter
    def hay_nuevos(self, valor):
        self.motor.hay_nuevos = valor

    def sincs(self):
        return self.motor.sincs()

    def sincronizar(self, nombre, resync=False):
        self.motor.sincronizar(nombre, resync)

    def sincronizar_todo(self):
        return self.motor.sincronizar_todo()

    def poner_pausa(self, pausar):
        self.motor.poner_pausa(pausar)

    def modificar_ajustes(self, funcion):
        self.motor.modificar_ajustes(funcion)

    def _otra_peticion(self, accion, nombre):
        if accion == "remontar" and nombre:
            self.remontar(nombre)
        elif accion == "salir":
            self.salir()

    # ------------------- vigilancia de cambios locales (inotify) -------------------
    def vigilar(self, nombre):
        self.dejar_de_vigilar(nombre)
        if not self.motor.sincs().get(nombre):
            return
        carpeta = self.motor.carpeta(nombre)
        if not os.path.isdir(carpeta):
            return
        monitores = []
        # También las carpetas ocultas (bisync las sincroniza igual); el límite de
        # MAX_MONITORES evita agotar inotify con carpetas enormes como .git
        for raiz, _dirs, _ in os.walk(carpeta):
            try:
                m = Gio.File.new_for_path(raiz).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            except GLib.Error:
                break                                    # límite de inotify alcanzado
            m.connect("changed", self._cambio, nombre)
            monitores.append(m)
            if len(monitores) >= MAX_MONITORES:
                break
        self.monitores[nombre] = monitores

    def dejar_de_vigilar(self, nombre):
        for m in self.monitores.pop(nombre, []):
            m.cancel()

    def _cambio(self, _monitor, archivo, _otro, evento, nombre):
        if evento in (Gio.FileMonitorEvent.ATTRIBUTE_CHANGED, Gio.FileMonitorEvent.PRE_UNMOUNT):
            return
        if archivo and nr.ignorar_archivo(archivo.get_basename() or ""):
            return
        self.motor.cambio_local(nombre)

    # ------------------------------ menú ------------------------------
    def menu_abierto(self):
        if self.hay_nuevos:
            self.hay_nuevos = False
            self.actualizar()
        return False

    def icono_registrado(self):
        if self.gtk:
            self.gtk.visible(False)

    def _comprobar_bandeja(self):
        if self.sni.registrado:
            return False
        if os.environ.get("DISPLAY"):
            try:
                self.gtk = IconoGtk(self)
                self.actualizar(forzar=True)
                return False
            except (ImportError, ValueError) as e:
                print("Sin respaldo GTK:", e, file=sys.stderr)
        if not self.aviso_sin_bandeja:
            self.aviso_sin_bandeja = True
            self.notificador.enviar(
                "No se encontró el área de notificaciones",
                "La sincronización sigue funcionando, pero tu escritorio no muestra iconos de "
                "bandeja. En GNOME instala la extensión «AppIndicator and KStatusNotifierItem "
                "Support».", "nubes-rclone")
        return False

    def estado_general(self):
        sincs = [n for n in self.sincs() if n in self.remotos]
        errores = [n for n in sincs if self.nubes.get(n, {}).get("estado") == "error"]
        if self.en_curso:
            return ("nubes-rclone-sync", "Sincronizando %s…" %
                    ", ".join("«%s»" % n for n in sorted(self.en_curso)))
        if self.ajustes.get("pausado") and sincs:
            return "nubes-rclone-pausa", "Sincronización en pausa"
        if errores:
            return "nubes-rclone-error", "Hay problemas con %s" % ", ".join("«%s»" % n for n in errores)
        if self.hay_nuevos:
            return "nubes-rclone-nuevo", "Hay archivos nuevos"
        if not sincs:
            return "nubes-rclone-ok", "No hay carpetas sincronizadas"
        return "nubes-rclone-ok", "Todo está al día"

    def _etiqueta_sinc(self, nombre):
        st = self.nubes.get(nombre, {})
        estado = st.get("estado", "pendiente")
        if nombre in self.en_curso:
            return "⟳ Sincronizando…"
        if self.ajustes.get("pausado"):
            return "⏸ En pausa"
        if estado == "error":
            return "⚠ Error"
        if estado == "ok":
            return "✔ Al día (%s)" % nr.hace(st.get("ultima"))
        return "… Pendiente"

    def modelo_menu(self):
        icono, resumen = self.estado_general()
        pausado = bool(self.ajustes.get("pausado"))
        nr_ajustes = self.ajustes
        menu = [{"texto": resumen, "activo": False}, {"sep": True}]

        for nombre in sorted(self.remotos):
            tipo = self.remotos[nombre]
            url = nr.URL_WEB.get(tipo)
            conf = self.sincs().get(nombre)
            hijos = []
            if conf:
                carpeta = os.path.expanduser(conf.get("carpeta") or nr.carpeta_sinc_defecto(nombre))
                st = self.nubes.get(nombre, {})
                hijos.append({"texto": "Última sincronización: %s" % nr.hace(st.get("ultima")),
                              "activo": False})
                if st.get("estado") == "error" and st.get("mensaje"):
                    hijos.append({"texto": "⚠ " + acortar(st["mensaje"], 70), "activo": False})
                hijos += [
                    {"sep": True},
                    {"texto": "Abrir carpeta local", "icono": "folder",
                     "accion": lambda c=carpeta: abrir(c)},
                ]
                punto = nr.punto_montaje(nombre, nr_ajustes)
                if nr.esta_montado(punto):
                    hijos.append({"texto": "Abrir carpeta de la nube (montada)", "icono": "folder-cloud",
                                  "accion": lambda p=punto: abrir(p)})
                if url:
                    hijos.append({"texto": "Abrir la nube en el navegador", "icono": "web-browser",
                                  "accion": lambda u=url: nr.abrir_url(u)})
                hijos += [
                    {"sep": True},
                    {"texto": "Sincronizar ahora", "icono": "view-refresh",
                     "activo": nombre not in self.en_curso and not pausado,
                     "accion": lambda n=nombre: self.sincronizar(n)},
                ]
                if st.get("estado") == "error" and "Reconectar sesión" in st.get("mensaje", ""):
                    hijos.append({"texto": "Reconectar sesión… (abre Lázaro Nubes)",
                                  "icono": "view-refresh", "accion": self.abrir_interfaz})
                if st.get("estado") == "error":
                    hijos.append({"texto": "Reparar (unir ambas copias sin borrar nada)",
                                  "activo": nombre not in self.en_curso and not pausado,
                                  "accion": lambda n=nombre: self.sincronizar(n, resync=True)})
                etiqueta = "%s — %s" % (nombre, self._etiqueta_sinc(nombre))
            else:
                punto = nr.punto_montaje(nombre, nr_ajustes)
                montada = nr.esta_montado(punto)
                if montada:
                    hijos.append({"texto": "Abrir carpeta de la nube", "icono": "folder-cloud",
                                  "accion": lambda p=punto: abrir(p)})
                else:
                    hijos.append({"texto": "Montar y abrir carpeta", "icono": "folder-cloud",
                                  "accion": lambda n=nombre: self.montar(n)})
                if url:
                    hijos.append({"texto": "Abrir la nube en el navegador", "icono": "web-browser",
                                  "accion": lambda u=url: nr.abrir_url(u)})
                if montada:
                    hijos.append({"texto": "Desmontar", "icono": "media-eject",
                                  "accion": lambda n=nombre: self.desmontar(n)})
                etiqueta = "%s — %s" % (nombre, "● Montada" if montada else "○ Sin montar")
            menu.append({"texto": etiqueta, "hijos": hijos})

        if not self.remotos:
            menu.append({"texto": "Aún no has conectado ninguna nube", "activo": False})

        menu.append({"sep": True})
        if self.recientes:
            hijos = []
            for r in self.recientes[:12]:
                conf = self.sincs().get(r["nube"])
                carpeta = os.path.expanduser((conf or {}).get("carpeta") or
                                             nr.carpeta_sinc_defecto(r["nube"]))
                ruta = os.path.join(carpeta, r["ruta"])
                hijos.append({
                    "texto": "%s %s · %s · %s" % (r["dir"], acortar(r["ruta"], 40), r["nube"], nr.hace(r["t"])),
                    "activo": os.path.exists(ruta),
                    "accion": lambda p=ruta: abrir(p)})
            hijos += [{"sep": True},
                      {"texto": "↓ = llegó desde la nube   ↑ = subido desde este equipo", "activo": False},
                      {"texto": "Vaciar la lista", "accion": self.vaciar_recientes}]
            titulo = "Archivos añadidos recientemente" + (" (nuevos)" if self.hay_nuevos else "")
            menu.append({"texto": titulo, "icono": "document-open-recent", "hijos": hijos})
        else:
            menu.append({"texto": "Sin archivos nuevos recientes", "activo": False})

        menu += [
            {"sep": True},
            {"texto": "Sincronizar todo ahora", "icono": "view-refresh",
             "activo": bool(self.sincs()) and not pausado, "accion": self.sincronizar_todo},
            {"texto": "Pausar sincronización", "marcado": pausado,
             "activo": bool(self.sincs()), "accion": lambda: self.poner_pausa(not pausado)},
            {"texto": "Velocidad máxima", "icono": "network-transmit-receive",
             "hijos": [{"texto": etiqueta, "marcado": self.ajustes.get("bwlimit", "") == valor,
                        "accion": lambda v=valor: self.cambiar_velocidad(v)}
                       for etiqueta, valor in nr.LIMITES_VELOCIDAD]},
            {"sep": True},
            {"texto": "Abrir Lázaro Nubes…", "icono": "nubes-rclone", "accion": self.abrir_interfaz},
        ]
        if self.ajustes.get("equipo_compartido"):
            menu += [{"texto": "Desconectar todas las cuentas (equipo compartido)",
                      "icono": "system-log-out",
                      "activo": bool(self.remotos) or self._hay_montajes(),
                      "accion": self.olvidar_cuentas}]
        menu += [
            {"texto": "Cerrar este icono", "icono": "application-exit", "accion": self.salir},
        ]
        return icono, resumen, menu

    def actualizar(self, forzar=False):
        icono, resumen, menu = self.modelo_menu()
        lineas = []
        for nombre in sorted(self.sincs()):
            if nombre in self.remotos:
                lineas.append("%s: %s" % (nombre, self._etiqueta_sinc(nombre)))
        texto = "\n".join(lineas) or "Haz clic para abrir Lázaro Nubes"

        def firma(m):
            return [(i.get("texto"), i.get("activo", True), i.get("marcado"),
                     firma(i["hijos"]) if i.get("hijos") else None) for i in m]
        f = (icono, resumen, texto, repr(firma(menu)))
        if forzar or f != self.firma_menu:
            self.firma_menu = f
            for destino in (self.sni, self.gtk):
                if destino:
                    destino.poner_icono(icono, nr.APP_NOMBRE + " — " + resumen, texto)
                    destino.poner_menu(menu)
        if getattr(self, "motor", None):
            self.motor.publicar_estado()
        return False

    # ----------------------------- acciones -----------------------------
    def cambiar_velocidad(self, valor):
        self.motor.modificar_ajustes(lambda a: a.update(bwlimit=valor))
        threading.Thread(target=nr.aplicar_bwlimit, args=(valor,), daemon=True).start()
        self.actualizar()

    def vaciar_recientes(self):
        self.motor.olvidar_recientes()
        self.actualizar()

    def alternar_ventana(self):
        """Clic izquierdo en el icono: abre la ventana, o la cierra si ya está abierta."""
        ahora = time.monotonic()
        if ahora - self.ultimo_clic < 1.0:      # doble clic: no abrir y cerrar de golpe
            return False
        self.ultimo_clic = ahora
        if nr.ventana_en_ejecucion():
            nr.pedir_cerrar_ventana()
        else:
            self.abrir_interfaz()
        return False

    def abrir_interfaz(self):
        # Si la ventana ya está abierta solo se trae al frente. Los clics repetidos
        # mientras la ventana todavía está arrancando se ignoran.
        ahora = time.monotonic()
        if nr.ventana_en_ejecucion():
            nr.pedir_mostrar_ventana()
        elif ahora - self.ultimo_lanzamiento > 5:
            self.ultimo_lanzamiento = ahora
            subprocess.Popen([sys.executable, os.path.join(DIR_APP, "nubes_rclone.py")],
                             stdin=subprocess.DEVNULL, start_new_session=True)
        return False

    def montar(self, nombre):
        def trabajo():
            ok, msg = nr.montar(nombre)
            GLib.idle_add(fin, ok, msg)

        def fin(ok, msg):
            punto = nr.punto_montaje(nombre)
            if ok:
                nr.anadir_marcador(punto, nombre)
                abrir(punto)
            else:
                self.notificador.enviar("No se pudo montar «%s»" % nombre, msg[:300], "nubes-rclone-error")
            self.actualizar()
            return False
        threading.Thread(target=trabajo, daemon=True).start()

    def remontar(self, nombre):
        """Desmonta y vuelve a montar (p. ej. tras actualizar la aplicación)."""
        def trabajo():
            nr.desmontar(nr.punto_montaje(nombre))
            ok, msg = nr.montar(nombre)
            GLib.idle_add(lambda: (self.actualizar(), False)[1])
            if not ok:
                GLib.idle_add(lambda: (self.notificador.enviar(
                    "No se pudo montar «%s»" % nombre, msg[:300], "nubes-rclone-error"), False)[1])
        threading.Thread(target=trabajo, daemon=True).start()

    def desmontar(self, nombre):
        # Desmontar puede tardar (programas usando archivos): en otro hilo, sin congelar el menú
        def trabajo():
            ok, msg = nr.desmontar(nr.punto_montaje(nombre))
            GLib.idle_add(fin, ok, msg)

        def fin(ok, msg):
            if not ok:
                self.notificador.enviar("No se pudo desmontar «%s»" % nombre, msg[:300],
                                        "nubes-rclone-error")
            self.actualizar()
            return False
        threading.Thread(target=trabajo, daemon=True).start()

    def _hay_montajes(self):
        base = os.path.realpath(os.path.expanduser(self.ajustes.get("carpeta_base", "")))
        return any(r == base or r.startswith(base + os.sep) for r, t in nr.montajes_actuales().items()
                   if t.startswith("fuse.rclone"))

    def olvidar_cuentas(self, al_iniciar=False):
        """Modo «equipo compartido»: desconecta y olvida todas las nubes."""
        self.motor.detener_procesos(signal.SIGTERM)

        def trabajo():
            # Al iniciar: solo la primera vez en esta sesión (si el icono se reinicia a
            # mitad de sesión no se borra lo que el docente acaba de conectar)
            problemas = nr.limpiar_sesion_si_hace_falta() if al_iniciar else nr.olvidar_todo()
            GLib.idle_add(fin, problemas)

        def fin(problemas):
            self.motor.recargar_ajustes()
            self.motor.leer_remotos()
            if problemas is not None:
                self.motor.olvidar_recientes()
            self.actualizar()
            if problemas:
                self.notificador.enviar(
                    "⚠ NO se pudieron desconectar todas las nubes",
                    "Siguen accesibles: %s. Cierra los programas que usan sus archivos y vuelve a "
                    "pulsar «Desconectar todas las cuentas», o cierra la sesión del equipo."
                    % ", ".join(problemas), "nubes-rclone-error")
            elif not al_iniciar:
                self.notificador.enviar(
                    "Cuentas desconectadas",
                    "Se desconectaron todas las nubes y se borró la caché. Cierra también tu sesión "
                    "de Google o Microsoft en el navegador antes de dejar el equipo.",
                    "nubes-rclone-ok")
            return False
        threading.Thread(target=trabajo, daemon=True).start()

    def salir(self):
        self.motor.detener_procesos(signal.SIGINT, esperar=20)
        self.bucle.quit()
        return False


def main():
    if Gio is None or "--sin-icono" in sys.argv:
        # Sin PyGObject no hay icono, pero la sincronización funciona igual
        print("Sin PyGObject (python3-gi / py3-gobject3): se sincroniza sin icono.", file=sys.stderr)
        import nubes_sinc
        return nubes_sinc.main()
    nr.asegurar_dir(nr.DIR_LOGS)
    nr.asegurar_dir(nr.DIR_EJEC)
    nr.asegurar_dir(nr.DIR_PETICIONES)
    bloqueo = open(nr.ARCHIVO_BLOQUEO_BANDEJA, "a")
    try:
        fcntl.flock(bloqueo, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("El icono de Lázaro Nubes ya está en ejecución.")
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
    bucle = GLib.MainLoop()
    try:
        bandeja = Bandeja(bucle)
    except GLib.Error as e:
        # Sin sesión D-Bus no puede haber icono, pero sí sincronización (Python puro)
        print("Sin sesión D-Bus (%s): se sincroniza sin icono." % e.message, file=sys.stderr)
        fcntl.flock(bloqueo, fcntl.LOCK_UN)
        bloqueo.close()
        import nubes_sinc
        return nubes_sinc.main()
    try:                                   # GLib >= 2.80
        from gi.repository import GLibUnix
        agregar_senal = GLibUnix.signal_add
    except ImportError:                    # versiones anteriores
        agregar_senal = GLib.unix_signal_add
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        agregar_senal(GLib.PRIORITY_DEFAULT, sig, bandeja.salir)
    bucle.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
