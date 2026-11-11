# Arreglos de Lázaro

Aquí van las mejoras que tienen que llegar a los equipos **ya instalados**
y que no son un programa nuevo, sino un cambio en el sistema: activar un
servicio, poner una tarea, corregir un archivo de configuración.

Los programas de Lázaro (Bienvenida, Afinador, Diagnóstico...) no
necesitan arreglo: se actualizan solos con el paquete
`lazaro-herramientas`. Un arreglo hace falta cuando el cambio está en lo
que se hace **una sola vez al instalar**, sobre todo en
`desktop-postinstall.sh`.

## Cómo llegan

1. El archivo se fusiona en `main`.
2. GitHub arma `lazaro-herramientas` con él adentro y lo firma.
3. En cada equipo, "Actualizar el sistema" instala el paquete y después
   corre `lazaro-arreglos --aplicar`, que ejecuta los arreglos que ese
   equipo todavía no tiene, en orden y una sola vez.
4. Al terminar, la ventana muestra el título de cada arreglo aplicado.

Nadie elige nada. Lo aplicado queda anotado en `/var/lib/lazaro/arreglos`
y el detalle en `/var/log/lazaro-arreglos.log`.

## Cómo escribir uno

Un archivo `NNN-nombre.sh` con el número siguiente al último (nunca se
reutiliza ni se cambia un número ya publicado):

```sh
#!/bin/sh
# Titulo: Lo que se hizo, dicho para quien usa el equipo
#
# Por qué hace falta y qué cambio de la instalación copia.

# ¿Hace falta en este equipo? Si no, 10.
[ -e /etc/algo ] || exit 10
# El cambio. Si no se puede ahora (sin internet), cualquier otro número:
# se intenta de nuevo en la próxima actualización.
hacer_algo || exit 1
exit 0
```

Reglas:

- **Primero la instalación.** El arreglo se agrega después (o junto con)
  el cambio en `desktop-postinstall.sh` o en la ISO. Un sistema recién
  instalado anota todos los arreglos de su ISO como hechos, sin correrlos.
- **Que pueda correr dos veces** sin romper nada, y que no dependa de
  otro arreglo.
- **Solo reparaciones.** Nada de gustos (fondos, temas, paneles): lo que
  la persona ajustó no se toca.
- **Un arreglo publicado no se edita.** Ya corrió en los equipos: para
  corregirlo se escribe otro.
- **Título traducido.** `python3 traducciones/extraer.py --actualizar` lo
  agrega a los archivos de idiomas; hay que traducirlo ahí.
- **Una prueba** en `pruebas/arreglos.sh`.

Lo grande (cambiar de kernel, los ajustes del Afinador) no va aquí: sigue
siendo decisión de la persona, desde su propio botón.
