# DockerLabs Scripts

Scripts para desplegar y gestionar laboratorios de [DockerLabs](https://dockerlabs.es) en macOS.

## Requisitos

- macOS (los scripts usan `osascript` y `open -a Docker`)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Archivos `.tar` de las máquinas descargados desde dockerlabs.es

## Estructura de directorios esperada

```
~/DockerLabs/
├── scripts/
│   ├── dockerlab.sh       ← script principal
│   └── auto_deploy.sh     ← script de despliegue
├── trust/
│   └── trust.tar
├── injection/
│   └── injection.tar
└── maquina.tar            ← también funciona en la raíz
```

## Scripts

### `dockerlab.sh` — Script principal

Automatiza todo el flujo: selección de máquina, despliegue, conexión de Kali y proxy web.

**Uso:**

```bash
bash ~/DockerLabs/scripts/dockerlab.sh
```

**Qué hace paso a paso:**

1. Extrae cualquier `.zip` descargado directamente en `~/DockerLabs/`
2. Arranca Docker Desktop si no está corriendo (espera hasta 90 segundos)
3. Escanea `~/DockerLabs/` buscando archivos `.tar` y muestra un menú numerado
4. Abre una nueva pestaña de Terminal ejecutando `auto_deploy.sh` con la máquina elegida
5. Detecta el contenedor nuevo y su red Docker aislada
6. Crea o reanuda un contenedor `kali-pentesting` (imagen `kalilinux/kali-rolling`) y lo conecta a la red de la víctima
7. Levanta un proxy `socat` que mapea `localhost:8080` → `IP_víctima:80` y abre el navegador automáticamente
8. Abre una shell interactiva dentro de `kali-pentesting`
9. Al salir de Kali, elimina el proxy

**Flujo resumido:**

```
dockerlab.sh
    │
    ├─ Nueva pestaña Terminal ──► auto_deploy.sh <máquina.tar>
    │                                  (gestiona el ciclo de vida del contenedor)
    │
    └─ Ventana actual
           ├─ kali-pentesting (conectado a la red de la víctima)
           ├─ Proxy: localhost:8080 → víctima:80
           └─ Shell interactiva en Kali
```

---

### `auto_deploy.sh` — Script de despliegue

Carga una imagen Docker desde un `.tar`, crea una red aislada y arranca el contenedor víctima. Se mantiene activo hasta que se pulsa `Ctrl+C`, momento en que limpia todos los recursos.

**Uso:**

```bash
sudo bash ~/DockerLabs/scripts/auto_deploy.sh /ruta/a/maquina.tar
```

> `dockerlab.sh` llama a este script automáticamente en una nueva pestaña. Úsalo de forma manual solo si quieres desplegar una máquina sin el flujo completo.

**Qué hace:**

1. Verifica que Docker esté corriendo (en macOS lo arranca si no está)
2. Carga la imagen con `docker load`
3. Crea una red aislada `<nombre>_net`
4. Arranca el contenedor `<nombre>_container` en esa red (con fallback `linux/amd64` para imágenes x86 en Apple Silicon)
5. Muestra la IP asignada al contenedor
6. Espera `Ctrl+C` para eliminar el contenedor, la red y la imagen

**Limpieza al pulsar `Ctrl+C`:**

```
Eliminando el laboratorio, espere un momento...
El laboratorio ha sido eliminado.
```

---

## Ejemplo de uso completo

```bash
# 1. Descarga una máquina desde dockerlabs.es y coloca el .tar en ~/DockerLabs/

# 2. Lanza el script principal
bash ~/DockerLabs/scripts/dockerlab.sh

# 3. Selecciona la máquina del menú
#    Se abre una pestaña con el despliegue y Kali se conecta automáticamente

# 4. Trabaja desde la shell de Kali
#    La web de la víctima está disponible en http://localhost:8080

# 5. Al terminar, sal de Kali con `exit`
#    El proxy se elimina solo
#    En la otra pestaña, pulsa Ctrl+C para eliminar el contenedor víctima
```

## Notas

- El contenedor `kali-pentesting` se reutiliza entre sesiones; no se elimina al salir.
- Si la máquina no tiene puerto 80, el proxy no se levanta pero el resto del flujo continúa.
- Los `.zip` descargados de la plataforma se extraen automáticamente y se eliminan tras la extracción.
