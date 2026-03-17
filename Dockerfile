#syntax=docker/dockerfile:1

ARG CEPH_IMG=quay.io/ceph/ceph
ARG CEPH_TAG=latest

FROM alpine:latest AS otto-fetcher

ARG OTTO_VERSION=latest

RUN apk add --no-cache curl && \
    curl -o /tmp/otto https://s3.clyso.com/otto/${OTTO_VERSION}/otto && \
    chmod +x /tmp/otto

FROM alpine:latest AS o8-fetcher

ARG O8_VERSION=latest

RUN apk add --no-cache curl && \
    curl -fsSL -o /tmp/o8 https://s3.clyso.com/o8s/${O8_VERSION}/o8 && \
    chmod +x /tmp/o8

FROM ${CEPH_IMG}:${CEPH_TAG} AS uwpmp-builder

RUN dnf install -y \
      git \
      cmake \
      gcc-c++ \
      elfutils-libelf-devel \
      elfutils-devel \
      autoconf \
      automake \
      libtool \
    && dnf clean all

RUN git clone https://github.com/JoshuaGabriel/uwpmp.git /tmp/uwpmp \
    && cd /tmp/uwpmp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make

FROM ${CEPH_IMG}:${CEPH_TAG}

RUN dnf install -y \
      elfutils-libs \
      strace \
      gdb \
      ltrace \
      lsof \
      tcpdump \
      sysstat \
      perf \
      bcc-tools \
      util-linux \
      procps-ng \
      iproute \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY --from=otto-fetcher /tmp/otto /usr/local/bin/otto
COPY --from=o8-fetcher /tmp/o8 /usr/local/bin/o8
COPY --from=uwpmp-builder /tmp/uwpmp/build/unwindpmp /usr/local/bin/unwindpmp
