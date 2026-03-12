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

echo "=== Detecting Ceph Version ==="

if [ -n "${CEPH_VERSION}" ]; then
    echo "Using provided CEPH_VERSION: ${CEPH_VERSION}"
else
    if [ -n "${CEPHADM_IMAGE}" ]; then
        RUNNING_IMAGE="${CEPHADM_IMAGE}"
    else
        RUNNING_IMAGE=$(podman ps --format "{{.Names}}\t{{.Image}}" | grep -E "^ceph-.*-(mon|mgr|osd|mds|rgw)-" | head -1 | awk '{print $2}' || true)

        if [ -z "${RUNNING_IMAGE}" ]; then
            RUNNING_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep "quay.io/ceph/ceph:v" | head -1 || true)
        fi
    fi

    if [ -n "${RUNNING_IMAGE}" ]; then
        CEPH_VERSION=$(podman inspect "${RUNNING_IMAGE}" --format '{{.RepoTags}}' 2>/dev/null | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' | head -1 || true)
        
        if [ -z "${CEPH_VERSION}" ]; then
            CEPH_VERSION=$(echo "${RUNNING_IMAGE}" | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' || true)
        fi
        
        if [ -n "${CEPH_VERSION}" ] && [[ "${CEPH_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Detected from cephadm container: ${CEPH_VERSION}"
        else
            CEPH_VERSION=""
        fi
    fi

    if [ -z "${CEPH_VERSION}" ] && command -v ceph &> /dev/null; then
        CEPH_VERSION=$(ceph version 2>/dev/null | grep -oP 'ceph version \K[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [ -n "${CEPH_VERSION}" ] && [[ "${CEPH_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Detected from ceph CLI: ${CEPH_VERSION}"
        else
            CEPH_VERSION=""
        fi
    fi

    if [ -z "${CEPH_VERSION}" ] && command -v rpm &> /dev/null; then
        CEPH_VERSION=$(rpm -q ceph-common --queryformat '%{VERSION}' 2>/dev/null || true)
        if [ -n "${CEPH_VERSION}" ] && [ "${CEPH_VERSION}" != "package ceph-common is not installed" ] && [[ "${CEPH_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Detected from RPM package: ${CEPH_VERSION}"
        else
            CEPH_VERSION=""
        fi
    fi

    if [ -z "${CEPH_VERSION}" ] && command -v dpkg &> /dev/null; then
        CEPH_VERSION=$(dpkg -s ceph-common 2>/dev/null | grep '^Version:' | awk '{print $2}' | cut -d'-' -f1 || true)
        if [ -n "${CEPH_VERSION}" ] && [[ "${CEPH_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Detected from DEB package: ${CEPH_VERSION}"
        else
            CEPH_VERSION=""
        fi
    fi
fi

if [ -z "${CEPH_VERSION}" ]; then
    echo "Error: Could not detect Ceph version"
    echo "Please set CEPH_VERSION environment variable:"
    echo "  CEPH_VERSION=18.2.7 $0"
    exit 1
fi

IMAGE="harbor.clyso.com/clyso-tools/clyso-tools:${CEPH_VERSION}"

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
  ${IMAGE} bash"

eval ${PODMAN_CMD}