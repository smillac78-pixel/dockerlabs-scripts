#!/usr/bin/env bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOCKERLABS_DIR="$HOME/DockerLabs"

info()    { echo -e "${BLUE}[*]${NC} $*"; }
ok()      { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[-]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# ── 0. Descomprimir ZIPs descargados de la plataforma ────────────────────────
extract_zips() {
    local found=0
    while IFS= read -r zipfile; do
        found=1
        info "ZIP encontrado: ${BOLD}$(basename "$zipfile")${NC} — descomprimiendo..."
        if unzip -q "$zipfile" -d "$DOCKERLABS_DIR"; then
            rm -f "$zipfile"
            ok "Descomprimido y eliminado: $(basename "$zipfile")"
        else
            error "Error al descomprimir: $zipfile"
        fi
    done < <(find "$DOCKERLABS_DIR" -maxdepth 1 -name "*.zip" 2>/dev/null)

    (( found )) && echo ""
}

# ── 1. Verificar / arrancar Docker Desktop ────────────────────────────────────
ensure_docker_running() {
    if docker info &>/dev/null; then
        return
    fi

    warn "Docker Desktop no está corriendo. Iniciándolo..."
    open -a Docker

    local MAX_WAIT=90
    local WAITED=0
    while (( WAITED < MAX_WAIT )); do
        sleep 3
        WAITED=$((WAITED + 3))
        printf "\r${BLUE}[*]${NC} Esperando Docker Desktop... %ds" "$WAITED"
        if docker info &>/dev/null; then
            echo ""
            ok "Docker Desktop listo."
            return
        fi
    done

    echo ""
    error "Docker Desktop no arrancó en ${MAX_WAIT}s. Ábrelo manualmente e inténtalo de nuevo."
    exit 1
}

# ── 2. Escanear máquinas disponibles ──────────────────────────────────────────
scan_machines() {
    MACHINES=()
    while IFS= read -r line; do
        MACHINES+=("$line")
    done < <(
        find "$DOCKERLABS_DIR" -maxdepth 2 \
            -not -path "$DOCKERLABS_DIR/scripts/*" \
            -name "*.tar" \
            2>/dev/null \
        | sed "s|$DOCKERLABS_DIR/||" \
        | sort
    )
}

show_menu() {
    header "══════════════════════════════════════"
    header "        DockerLabs - Menú principal    "
    header "══════════════════════════════════════"

    if [[ ${#MACHINES[@]} -eq 0 ]]; then
        error "No se encontraron archivos .tar en $DOCKERLABS_DIR"
        exit 1
    fi

    echo ""
    for i in "${!MACHINES[@]}"; do
        printf "  ${BOLD}%2d)${NC} %s\n" "$((i+1))" "${MACHINES[$i]}"
    done
    echo -e "   ${RED}0)${NC} Salir"
    echo ""
}

# ── 3. Selección del usuario ───────────────────────────────────────────────────
pick_machine() {
    local max=${#MACHINES[@]}
    while true; do
        read -rp "$(echo -e "${CYAN}Selecciona una máquina [1-${max}] / 0 para salir: ${NC}")" choice
        if [[ "$choice" == "0" ]]; then
            info "Saliendo."
            exit 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            TAR_REL="${MACHINES[$((choice-1))]}"   # ej: nombre/nombre.tar  o  nombre.tar
            TAR_NAME="$(basename "$TAR_REL")"      # ej: nombre.tar
            MACHINE_DIR="$(dirname "$TAR_REL")"    # ej: nombre  o  .
            if [[ "$MACHINE_DIR" == "." ]]; then
                MACHINE_DIR="${TAR_NAME%.tar}"
            fi
            ok "Máquina seleccionada: ${BOLD}$TAR_NAME${NC}"
            return
        else
            warn "Opción inválida. Intenta de nuevo."
        fi
    done
}

# ── 3. Desplegar la máquina ────────────────────────────────────────────────────
deploy_machine() {
    local deploy_script="$DOCKERLABS_DIR/scripts/auto_deploy.sh"
    local tar_path="$DOCKERLABS_DIR/$TAR_REL"

    if [[ ! -f "$deploy_script" ]]; then
        error "No se encontró el script universal: $deploy_script"
        exit 1
    fi

    if [[ ! -f "$tar_path" ]]; then
        error "No se encontró el archivo: $tar_path"
        exit 1
    fi

    info "Abriendo pestaña de control para ${BOLD}$TAR_NAME${NC}..."
    info "(Pulsa Ctrl+C en esa pestaña cuando termines para eliminar la máquina)"

    osascript -e "tell application \"Terminal\"
        activate
        tell application \"System Events\" to keystroke \"t\" using {command down}
        delay 0.4
        do script \"sudo bash '$deploy_script' '$tar_path'\" in front window
        set custom title of front window to \"Lab - $MACHINE_DIR\"
    end tell" 2>/dev/null

    sleep 1
}

# ── 4. Esperar a que el contenedor esté corriendo ─────────────────────────────
wait_for_container() {
    info "Esperando a que el contenedor arranque"
    local SECONDS_WAITED=0
    local MAX_WAIT=60

    # Captura los contenedores existentes antes del despliegue para comparar
    local before
    before=$(docker ps -q 2>/dev/null)

    while (( SECONDS_WAITED < MAX_WAIT )); do
        sleep 2
        SECONDS_WAITED=$((SECONDS_WAITED + 2))
        printf "\r${BLUE}[*]${NC} Esperando... %ds" "$SECONDS_WAITED"

        local after
        after=$(docker ps -q 2>/dev/null)

        NEW_CONTAINER_ID=$(comm -13 \
            <(echo "$before" | sort) \
            <(echo "$after"  | sort) \
            | head -1)

        if [[ -n "$NEW_CONTAINER_ID" ]]; then
            echo ""
            ok "Contenedor detectado: ${BOLD}$NEW_CONTAINER_ID${NC}"
            return
        fi
    done

    echo ""
    error "Tiempo de espera agotado. No se detectó ningún contenedor nuevo."
    error "Revisa que el auto_deploy.sh esté funcionando en la otra ventana."
    exit 1
}

# ── 5. Detectar nombre e info del contenedor ──────────────────────────────────
get_container_info() {
    CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter "id=$NEW_CONTAINER_ID" 2>/dev/null)
    if [[ -z "$CONTAINER_NAME" ]]; then
        CONTAINER_NAME="$NEW_CONTAINER_ID"
    fi
    ok "Nombre del contenedor: ${BOLD}$CONTAINER_NAME${NC}"
}

# ── 6. Detectar la red Docker del contenedor ──────────────────────────────────
detect_network() {
    info "Detectando la red del contenedor..."

    DOCKER_NETWORK=$(docker inspect "$NEW_CONTAINER_ID" \
        --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null \
        | grep -v '^bridge$' | head -1)

    # Fallback: cualquier red incluida bridge
    if [[ -z "$DOCKER_NETWORK" ]]; then
        DOCKER_NETWORK=$(docker inspect "$NEW_CONTAINER_ID" \
            --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null \
            | head -1)
    fi

    if [[ -z "$DOCKER_NETWORK" ]]; then
        error "No se pudo detectar la red del contenedor."
        exit 1
    fi

    ok "Red detectada: ${BOLD}$DOCKER_NETWORK${NC}"
}

# ── 7. Verificar / crear contenedor kali-pentesting ───────────────────────────
ensure_kali_container() {
    info "Verificando contenedor kali-pentesting..."

    if docker ps -a --format '{{.Names}}' | grep -q '^kali-pentesting$'; then
        # Existe, ¿está corriendo?
        if ! docker ps --format '{{.Names}}' | grep -q '^kali-pentesting$'; then
            warn "El contenedor kali-pentesting existe pero está parado. Iniciándolo..."
            docker start kali-pentesting &>/dev/null
        fi
        ok "Contenedor kali-pentesting ya existe y está activo."
    else
        info "Creando contenedor kali-pentesting..."
        if docker run -dit --name kali-pentesting kalilinux/kali-rolling bash &>/dev/null; then
            ok "Contenedor kali-pentesting creado correctamente."
        else
            error "Error al crear el contenedor kali-pentesting."
            exit 1
        fi
    fi
}

# ── 8. Conectar kali-pentesting a la red detectada ────────────────────────────
connect_to_network() {
    info "Conectando kali-pentesting a la red ${BOLD}$DOCKER_NETWORK${NC}..."
    local out
    out=$(docker network connect "$DOCKER_NETWORK" kali-pentesting 2>&1)
    if echo "$out" | grep -qi "already exists"; then
        warn "kali-pentesting ya está conectado a $DOCKER_NETWORK (ignorando error)."
    elif [[ $? -ne 0 && -n "$out" ]]; then
        warn "Advertencia al conectar: $out"
    else
        ok "Conexión establecida en la red $DOCKER_NETWORK."
    fi
}

# ── 9. Obtener IP de la máquina víctima ───────────────────────────────────────
get_target_ip() {
    TARGET_IP=$(docker inspect "$NEW_CONTAINER_ID" \
        --format "{{(index .NetworkSettings.Networks \"$DOCKER_NETWORK\").IPAddress}}" 2>/dev/null)

    if [[ -z "$TARGET_IP" ]]; then
        warn "No se pudo obtener la IP de la víctima. El proxy web no estará disponible."
    else
        ok "IP de la víctima:    ${BOLD}$TARGET_IP${NC}"
    fi
}

# ── 10. Levantar proxy socat (puerto 80 víctima → localhost:8080) ─────────────
start_proxy() {
    [[ -z "$TARGET_IP" ]] && return

    info "Levantando proxy web ${BOLD}localhost:8080${NC} → ${BOLD}$TARGET_IP:80${NC}..."

    # Eliminar proxy anterior si existiera
    docker rm -f proxy-web &>/dev/null

    # Arrancamos en bridge para que -p publique el puerto al host correctamente,
    # luego conectamos a la red de la víctima para que socat pueda alcanzarla
    docker run -d --rm --name proxy-web \
        -p 8080:80 \
        alpine/socat \
        TCP-LISTEN:80,fork,reuseaddr "TCP:$TARGET_IP:80" &>/dev/null

    if [[ $? -ne 0 ]]; then
        warn "No se pudo levantar el proxy. Puede que la máquina no tenga puerto 80."
        return
    fi

    # Conectar a la red de la víctima para que socat pueda alcanzarla
    docker network connect "$DOCKER_NETWORK" proxy-web &>/dev/null

    # Esperar 3 segundos para que el proxy levante sobre contenido fresco
    info "Esperando 3 segundos para que el proxy esté listo..."
    sleep 3

    ok "Abriendo ${BOLD}http://localhost:8080${NC}"
    open "http://localhost:8080?nocache=$RANDOM"
}

# ── 11. Entrar al contenedor kali-pentesting ──────────────────────────────────
enter_kali() {
    echo ""
    header "══════════════════════════════════════"
    ok "Máquina desplegada:  ${BOLD}$CONTAINER_NAME${NC}"
    [[ -n "$TARGET_IP" ]] && ok "IP del objetivo:     ${BOLD}$TARGET_IP${NC}"
    ok "Red:                 ${BOLD}$DOCKER_NETWORK${NC}"
    [[ -n "$TARGET_IP" ]] && ok "Web (proxy):         ${BOLD}http://localhost:8080${NC}"
    header "══════════════════════════════════════"
    echo ""
    info "Entrando a kali-pentesting... (al salir se eliminará el proxy)"
    echo ""

    docker exec -it kali-pentesting bash

    # ── Al salir de kali: limpiar proxy ───────────────────────────────────────
    echo ""
    info "Sesión de Kali finalizada. Eliminando proxy web..."
    docker rm -f proxy-web &>/dev/null && ok "Proxy eliminado." || warn "El proxy ya no existía."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    extract_zips
    ensure_docker_running
    scan_machines
    show_menu
    pick_machine
    deploy_machine
    wait_for_container
    get_container_info
    detect_network
    ensure_kali_container
    connect_to_network
    get_target_ip
    start_proxy
    enter_kali
}

main
