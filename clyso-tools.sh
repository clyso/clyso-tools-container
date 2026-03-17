#!/bin/bash

set -e

usage() {
    echo "Usage: $0 -v|--version <ceph_version> [-c|--config <config_path>] [-k|--keyring <keyring_path>] [-e|--engine <engine>]"
    echo ""
    echo "Required:"
    echo "  -v, --version <version>    Ceph version (e.g., 18.2.7)"
    echo ""
    echo "Optional:"
    echo "  -c, --config <path>        Path to ceph.conf (otherwise auto-detected)"
    echo "  -k, --keyring <path>       Path to keyring file (otherwise auto-detected)"
    echo "  -e, --engine <engine>      Container engine (podman or docker, auto-detected if not specified)"
    echo "  -h, --help                 Show this help message"
    exit 1
}

CEPH_VERSION=""
CONFIG_FLAG=""
KEYRING_FLAG=""
ENGINE_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            CEPH_VERSION="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FLAG="$2"
            shift 2
            ;;
        -k|--keyring)
            KEYRING_FLAG="$2"
            shift 2
            ;;
        -e|--engine)
            ENGINE_FLAG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "${CEPH_VERSION}" ]; then
    echo "Error: --version flag is required"
    usage
fi

echo "=== Detecting Container Engine ==="
CONTAINER_ENGINE=""

if [ -n "${ENGINE_FLAG}" ]; then
    if command -v "${ENGINE_FLAG}" &> /dev/null; then
        CONTAINER_ENGINE="${ENGINE_FLAG}"
        echo "Using specified engine: ${CONTAINER_ENGINE}"
    else
        echo "Error: Specified container engine '${ENGINE_FLAG}' not found"
        exit 1
    fi
else
    PODMAN_HAS_CEPH=false
    DOCKER_HAS_CEPH=false
    
    if command -v podman &> /dev/null; then
        if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "^ceph-"; then
            PODMAN_HAS_CEPH=true
        fi
    fi
    
    if command -v docker &> /dev/null; then
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ceph-"; then
            DOCKER_HAS_CEPH=true
        fi
    fi
    
    if [ "$PODMAN_HAS_CEPH" = true ] && [ "$DOCKER_HAS_CEPH" = false ]; then
        CONTAINER_ENGINE="podman"
        echo "Detected Ceph containers in: podman"
    elif [ "$DOCKER_HAS_CEPH" = true ] && [ "$PODMAN_HAS_CEPH" = false ]; then
        CONTAINER_ENGINE="docker"
        echo "Detected Ceph containers in: docker"
    elif [ "$PODMAN_HAS_CEPH" = true ] && [ "$DOCKER_HAS_CEPH" = true ]; then
        echo "Warning: Ceph containers found in both podman and docker"
        echo "Defaulting to podman. Use --engine to specify explicitly."
        CONTAINER_ENGINE="podman"
    else
        if command -v podman &> /dev/null; then
            CONTAINER_ENGINE="podman"
            echo "No Ceph containers detected. Using available engine: podman"
        elif command -v docker &> /dev/null; then
            CONTAINER_ENGINE="docker"
            echo "No Ceph containers detected. Using available engine: docker"
        else
            echo "Error: No container engine found (podman or docker required)"
            exit 1
        fi
    fi
fi

DATA_DIR="/var/lib/ceph"

echo "=== Inferring FSID ==="
FSIDS=($(ls -d ${DATA_DIR}/*-*-*-*-* 2>/dev/null | xargs -n1 basename || true))

if [ ${#FSIDS[@]} -eq 0 ]; then
    echo "Error: No FSID found in ${DATA_DIR}"
    exit 1
else
    FSID="${FSIDS[0]}"
    echo "Inferred FSID: ${FSID}"
fi

echo "=== Inferring Config ==="
CONFIG=""

if [ -n "${CONFIG_FLAG}" ]; then
    if [ -f "${CONFIG_FLAG}" ]; then
        CONFIG="${CONFIG_FLAG}"
        echo "Using provided config: ${CONFIG}"
    else
        echo "Error: Provided config file not found: ${CONFIG_FLAG}"
        exit 1
    fi
elif [ -f "${DATA_DIR}/${FSID}/config/ceph.conf" ]; then
    CONFIG="${DATA_DIR}/${FSID}/config/ceph.conf"
    echo "Found config: ${CONFIG}"
elif [ -f "/etc/ceph/ceph.conf" ]; then
    CONFIG="/etc/ceph/ceph.conf"
    echo "Using default config: ${CONFIG}"
else
    echo "Error: No config file found"
    exit 1
fi

echo "=== Inferring Keyring ==="
KEYRING=""

if [ -n "${KEYRING_FLAG}" ]; then
    if [ -f "${KEYRING_FLAG}" ]; then
        KEYRING="${KEYRING_FLAG}"
        echo "Using provided keyring: ${KEYRING}"
    else
        echo "Error: Provided keyring file not found: ${KEYRING_FLAG}"
        exit 1
    fi
elif [ -f "${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring" ]; then
    KEYRING="${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring"
    echo "Found keyring: ${KEYRING}"
elif [ -f "/etc/ceph/ceph.client.admin.keyring" ]; then
    KEYRING="/etc/ceph/ceph.client.admin.keyring"
    echo "Using default keyring: ${KEYRING}"
else
    echo "Warning: No keyring found"
    exit 1
fi

echo "=== Using Ceph Version ==="
echo "Ceph version: ${CEPH_VERSION}"

IMAGE="harbor.clyso.com/clyso-tools/clyso-tools:${CEPH_VERSION}"

echo "Container Engine: ${CONTAINER_ENGINE}"
echo "FSID:            ${FSID}"
echo "Config:          ${CONFIG}"
echo "Keyring:         ${KEYRING}"
echo "Image:           ${IMAGE}"
echo ""

CONTAINER_CMD="${CONTAINER_ENGINE} run -it --rm \
  --name clyso-tools \
  --net=host \
  -e CONTAINER_IMAGE=${IMAGE} \
  -e NODE_NAME=$(hostname) \
  -e LANG=C \
  -v ${CONFIG}:/etc/ceph/ceph.conf:z \
  -v ${KEYRING}:/etc/ceph/ceph.keyring:z \
  -v /:/rootfs:ro \
  ${IMAGE} bash"

eval ${CONTAINER_CMD}