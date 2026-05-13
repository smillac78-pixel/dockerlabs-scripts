#!/bin/bash

BOLD='\033[1m'
RED='\033[1;91m'
YELLOW='\033[1;93m'
CYAN='\033[1;96m'
WHITE='\033[1;97m'
GREEN='\033[1;32m'
NC='\033[0m'

TAR_FILE="$1"
IMAGE_NAME=""
CONTAINER_NAME=""
NETWORK_NAME=""

cleanup() {
    echo -e "\n${BOLD}Eliminando el laboratorio, espere un momento...${NC}"
    [[ -n "$CONTAINER_NAME" ]] && docker rm -f "$CONTAINER_NAME" &>/dev/null
    [[ -n "$NETWORK_NAME"   ]] && docker network rm "$NETWORK_NAME" &>/dev/null
    [[ -n "$IMAGE_NAME"     ]] && docker rmi "$IMAGE_NAME" &>/dev/null
    echo -e "El laboratorio ha sido eliminado."
    exit 0
}

trap cleanup INT

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 <archivo.tar>"
    exit 1
fi

if [[ ! -f "$TAR_FILE" ]]; then
    echo -e "${RED}Error: no se encuentra el archivo: $TAR_FILE${NC}"
    exit 1
fi

# ── Docker daemon ─────────────────────────────────────────────────────────────
if ! docker info &>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${CYAN}Docker Desktop no está corriendo. Iniciando...${NC}"
        open -a Docker
        echo -n "Esperando"
        for i in {1..30}; do
            docker info &>/dev/null && { echo ""; break; }
            echo -n "."
            sleep 2
        done
        if ! docker info &>/dev/null; then
            echo -e "\n${RED}Error: Docker Desktop no arrancó. Ábrelo manualmente e intenta de nuevo.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}El daemon de Docker no está corriendo. Ejecuta: sudo systemctl start docker${NC}"
        exit 1
    fi
fi

# ── Nombres ───────────────────────────────────────────────────────────────────
BASE_NAME="$(basename "$TAR_FILE" .tar)"
CONTAINER_NAME="${BASE_NAME}_container"
NETWORK_NAME="${BASE_NAME}_net"

# ── Limpieza previa ───────────────────────────────────────────────────────────
echo -e "${YELLOW}\nEstamos desplegando la máquina vulnerable, espere un momento.${NC}"
docker rm -f "$CONTAINER_NAME" &>/dev/null
docker network rm "$NETWORK_NAME" &>/dev/null

# ── Cargar imagen ─────────────────────────────────────────────────────────────
LOAD_OUTPUT=$(docker load -i "$TAR_FILE" 2>&1)
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error al cargar la imagen:\n$LOAD_OUTPUT${NC}"
    exit 1
fi

# docker load imprime "Loaded image: nombre:tag"  o  "Loaded image ID: sha256:..."
IMAGE_NAME=$(echo "$LOAD_OUTPUT" | awk '/Loaded image:/{print $NF}' | head -1)
[[ -z "$IMAGE_NAME" ]] && IMAGE_NAME=$(echo "$LOAD_OUTPUT" | grep -o 'sha256:[a-f0-9]*' | head -1)
[[ -z "$IMAGE_NAME" ]] && IMAGE_NAME="$BASE_NAME"   # último recurso

echo -e "${GREEN}Imagen cargada: ${WHITE}$IMAGE_NAME${NC}"

# ── Red aislada ───────────────────────────────────────────────────────────────
docker network create "$NETWORK_NAME" &>/dev/null

# ── Arrancar contenedor (fallback ARM → x86) ──────────────────────────────────
if ! docker run -d --network="$NETWORK_NAME" --name "$CONTAINER_NAME" "$IMAGE_NAME" &>/dev/null; then
    if ! docker run --platform linux/amd64 -d --network="$NETWORK_NAME" --name "$CONTAINER_NAME" "$IMAGE_NAME" &>/dev/null; then
        echo -e "${RED}Error al arrancar el contenedor.${NC}"
        docker network rm "$NETWORK_NAME" &>/dev/null
        exit 1
    fi
fi

# ── IP ────────────────────────────────────────────────────────────────────────
IP_ADDRESS=$(docker inspect -f \
    "{{(index .NetworkSettings.Networks \"$NETWORK_NAME\").IPAddress}}" \
    "$CONTAINER_NAME" 2>/dev/null)
[[ -z "$IP_ADDRESS" ]] && \
    IP_ADDRESS=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "$CONTAINER_NAME" 2>/dev/null)

echo -e "${CYAN}\nMáquina desplegada, su dirección IP es --> ${WHITE}$IP_ADDRESS${NC}"
echo -e "${RED}\nPresiona Ctrl+C cuando termines para eliminar la máquina${NC}"

while true; do sleep 1; done
