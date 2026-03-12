#!/bin/bash

set -e

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

if [ -f "${DATA_DIR}/${FSID}/config/ceph.conf" ]; then
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

if [ -f "${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring" ]; then
    KEYRING="${DATA_DIR}/${FSID}/config/ceph.client.admin.keyring"
    echo "Found keyring: ${KEYRING}"
elif [ -f "/etc/ceph/ceph.client.admin.keyring" ]; then
    KEYRING="/etc/ceph/ceph.client.admin.keyring"
    echo "Using default keyring: ${KEYRING}"
else
    echo "Warning: No keyring found"
    exit 1
fi

echo "=== Inferring Image ==="
IMAGE=""

if [ -n "${CEPHADM_IMAGE}" ]; then
    IMAGE="${CEPHADM_IMAGE}"
    echo "Using CEPHADM_IMAGE: ${IMAGE}"
else
    IMAGE=$(podman ps \
        --filter "label=ceph=True" \
        --format "{{.Image}}" | head -1 || true)

    if [ -n "${IMAGE}" ]; then
        echo "Inferred from running containers: ${IMAGE}"
    else
        IMAGE=$(podman images \
            --filter "label=ceph=True" \
            --filter "dangling=false" \
            --format "{{.Repository}}:{{.Tag}}" | head -1 || true)

        if [ -n "${IMAGE}" ]; then
            echo "Using most recent Ceph image on host: ${IMAGE}"
        else
            IMAGE="quay.ceph.io/ceph-ci/ceph:main"
            echo "Using default image: ${IMAGE}"
        fi
    fi
fi

#echo "=== Downloading o8 binary ==="
#O8_BINARY_URL="https://github.com/clyso/rgw-tui/releases/download/v0.1.0/o8"
O8_BINARY_PATH="/tmp/o8"
#curl -fsSL "${O8_BINARY_URL}" -o "${O8_BINARY_PATH}"
#chmod +x "${O8_BINARY_PATH}"

echo "FSID:    ${FSID}"
echo "Config:  ${CONFIG}"
echo "Keyring: ${KEYRING}"
echo "Image:   ${IMAGE}"
echo "O8 Binary:  ${O8_BINARY_PATH}"
echo ""

PODMAN_CMD="podman run -it --rm \
  --name clyso-tools \
  --net=host \
  -e CONTAINER_IMAGE=${IMAGE} \
  -e NODE_NAME=$(hostname) \
  -e LANG=C \
  -v ${CONFIG}:/etc/ceph/ceph.conf:z \
  -v ${KEYRING}:/etc/ceph/ceph.keyring:z \
  -v ${O8_BINARY_PATH}:/usr/local/bin/o8:ro \
  ${IMAGE} bash"

eval ${PODMAN_CMD}