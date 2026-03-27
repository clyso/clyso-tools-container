#!/bin/bash

set -e

usage() {
    echo "Usage: $0 -v|--version <ceph_version> [-c|--config <config_path>] [-k|--keyring <keyring_path>] [-e|--engine <engine>] [-- <command>]"
    echo ""
    echo "Required:"
    echo "  -v, --version <version>    Ceph version (e.g., 18.2.7)"
    echo ""
    echo "Optional:"
    echo "  -c, --config <path>        Path to ceph.conf (otherwise auto-detected)"
    echo "  -k, --keyring <path>       Path to keyring file (otherwise auto-detected)"
    echo "  -e, --engine <engine>      Container engine (podman or docker, auto-detected if not specified)"
    echo "  -d, --debug                Enable debug mode (--pid=host, SYS_PTRACE, SYS_ADMIN, seccomp=unconfined)"
    echo "                             Required for tracing operations (osdtrace, radostrace) on non-admin nodes"
    echo "  -p, --pull                 Pull the latest image before running"
    echo "  -n, --dry-run              Print the container run command without executing it"
    echo "  -h, --help                 Show this help message"
    exit 1
}

CEPH_VERSION=""
CONFIG_FLAG=""
KEYRING_FLAG=""
ENGINE_FLAG=""
DEBUG_MODE=false
PULL_MODE=false
DRY_RUN=false
COMMAND_ARGS=()

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
        -d|--debug)
            DEBUG_MODE=true
            shift
            ;;
        -p|--pull)
            PULL_MODE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            COMMAND_ARGS=("$@")
            break
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
FSID=""

FSIDS=($(ls -d ${DATA_DIR}/*-*-*-*-* 2>/dev/null | xargs -n1 basename 2>/dev/null || true))

if [ ${#FSIDS[@]} -gt 0 ]; then
    FSID="${FSIDS[0]}"
    echo "Inferred FSID: ${FSID}"
else
    echo "No FSID found in ${DATA_DIR}"
fi

CONFIG=""

if [ -n "${CONFIG_FLAG}" ]; then
    if [ -f "${CONFIG_FLAG}" ]; then
        CONFIG="${CONFIG_FLAG}"
        echo "Using provided config: ${CONFIG}"
    else
        echo "Error: Provided config file not found: ${CONFIG_FLAG}"
        exit 1
    fi
elif [ -n "${FSID}" ] && [ -f "${DATA_DIR}/${FSID}/config/ceph.conf" ]; then
    CONFIG="${DATA_DIR}/${FSID}/config/ceph.conf"
    echo "Found config: ${CONFIG}"
elif [ -f "/etc/ceph/ceph.conf" ]; then
    CONFIG="/etc/ceph/ceph.conf"
    echo "Using default config: ${CONFIG}"
else
    if [ "${DEBUG_MODE}" = true ]; then
        echo "Warning: No config file found (continuing in debug mode for tracing operations)"
        CONFIG=""
    else
        echo "Error: No config file found"
        echo "Hint: Use --debug flag to run without config for tracing operations"
        exit 1
    fi
fi

KEYRING=""

if [ -n "${KEYRING_FLAG}" ]; then
    if [ -f "${KEYRING_FLAG}" ]; then
        KEYRING="${KEYRING_FLAG}"
        echo "Using provided keyring: ${KEYRING}"
    else
        echo "Error: Provided keyring file not found: ${KEYRING_FLAG}"
        exit 1
    fi
elif [ -n "${FSID}" ] && [ -f "${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring" ]; then
    KEYRING="${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring"
    echo "Found keyring: ${KEYRING}"
elif [ -f "/etc/ceph/ceph.client.admin.keyring" ]; then
    KEYRING="/etc/ceph/ceph.client.admin.keyring"
    echo "Using default keyring: ${KEYRING}"
else
    if [ "${DEBUG_MODE}" = true ]; then
        echo "Warning: No keyring found (continuing in debug mode for tracing operations)"
        KEYRING=""
    else
        echo "Error: No keyring found"
        echo "Hint: Use --debug flag to run without keyring for tracing operations"
        exit 1
    fi
fi

echo "Ceph version: ${CEPH_VERSION}"

IMAGE="harbor.clyso.com/clyso-tools/clyso-tools:${CEPH_VERSION}"
echo "Image:           ${IMAGE}"
echo ""

# --security-opt apparmor=unconfined is needed for OSDs processes with unwindpmp
DEBUG_FLAGS=""
if [ "${DEBUG_MODE}" = true ]; then
    DEBUG_FLAGS="--pid=host --cap-add=SYS_PTRACE --cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined"
fi

if [ "${PULL_MODE}" = true ]; then
    ${CONTAINER_ENGINE} pull "${IMAGE}" || exit 1
    
fi

if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
    INTERACTIVE_FLAGS=""
    ENTRYPOINT="--entrypoint ${COMMAND_ARGS[0]}"
    TRAILING_ARGS="${COMMAND_ARGS[@]:1}"
else
    INTERACTIVE_FLAGS="-it"
    ENTRYPOINT="--entrypoint bash"
    TRAILING_ARGS=""
fi

VOLUME_MOUNTS=""
if [ -n "${CONFIG}" ]; then
    VOLUME_MOUNTS="${VOLUME_MOUNTS} -v ${CONFIG}:/etc/ceph/ceph.conf:z"
fi
if [ -n "${KEYRING}" ]; then
    VOLUME_MOUNTS="${VOLUME_MOUNTS} -v ${KEYRING}:/etc/ceph/ceph.keyring:z"
fi

CONTAINER_CMD="${CONTAINER_ENGINE} run ${INTERACTIVE_FLAGS} --rm \
  --name clyso-tools-$$ \
  --net=host \
  ${DEBUG_FLAGS} \
  ${ENTRYPOINT} \
  -e CONTAINER_IMAGE=${IMAGE} \
  -e NODE_NAME=$(hostname) \
  -e LANG=C \
  ${VOLUME_MOUNTS} \
  -v /:/rootfs:z \
  ${IMAGE} ${TRAILING_ARGS}"

if [ "${DRY_RUN}" = true ]; then
    echo "${CONTAINER_CMD}"
else
    eval ${CONTAINER_CMD}
fi
