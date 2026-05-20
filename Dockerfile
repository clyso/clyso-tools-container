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

RUN git clone https://github.com/markhpc/uwpmp.git /tmp/uwpmp \
    && cd /tmp/uwpmp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make

FROM ${CEPH_IMG}:${CEPH_TAG} AS cephtrace-builder

RUN dnf install -y \
      git \
      gcc \
      gcc-c++ \
      clang \
      make \
      elfutils-libelf-devel \
      elfutils-devel \
      glibc-devel \
      glibc-devel.i686 \
      openssl-devel \
    && dnf clean all

RUN git clone https://github.com/taodd/cephtrace.git /tmp/cephtrace && \
    cd /tmp/cephtrace && \
    git submodule update --init --recursive && \
    make -j $(nproc) osdtrace radostrace

RUN cd /tmp && \
    CEPH_VERSION=$(rpm -q ceph-osd --queryformat '%{VERSION}-%{RELEASE}') && \
    dnf install -y \
      https://download.ceph.com/rpm-${CEPH_VERSION%-*}/el9/x86_64/ceph-debuginfo-${CEPH_VERSION}.x86_64.rpm \
      https://download.ceph.com/rpm-${CEPH_VERSION%-*}/el9/x86_64/ceph-osd-debuginfo-${CEPH_VERSION}.x86_64.rpm \
      https://download.ceph.com/rpm-${CEPH_VERSION%-*}/el9/x86_64/librados2-debuginfo-${CEPH_VERSION}.x86_64.rpm \
      https://download.ceph.com/rpm-${CEPH_VERSION%-*}/el9/x86_64/librbd1-debuginfo-${CEPH_VERSION}.x86_64.rpm \
    && dnf clean all

RUN cd /tmp/cephtrace && \
    CEPH_FULL_VERSION=$(rpm -q ceph-osd --queryformat '%{EPOCH}:%{VERSION}-%{RELEASE}') && \
    ./osdtrace -j /tmp/osdtrace-dwarf.json && \
    ./radostrace -j /tmp/radostrace-dwarf.json && \
    ls -lh /tmp/*-dwarf.json

FROM ${CEPH_IMG}:${CEPH_TAG}
# cephadm shell picks images based on this flag, removing this helps cephadm not get confused to use this image
LABEL ceph="" 

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
      fio \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY --from=otto-fetcher /tmp/otto /usr/local/bin/otto
COPY --from=o8-fetcher /tmp/o8 /usr/local/bin/o8
COPY --from=uwpmp-builder /tmp/uwpmp/build/unwindpmp /usr/local/bin/unwindpmp

COPY --from=cephtrace-builder /tmp/cephtrace/osdtrace /usr/local/bin/osdtrace
COPY --from=cephtrace-builder /tmp/cephtrace/radostrace /usr/local/bin/radostrace

RUN mkdir -p /usr/local/share/cephtrace
COPY --from=cephtrace-builder /tmp/osdtrace-dwarf.json /usr/local/share/cephtrace/
COPY --from=cephtrace-builder /tmp/radostrace-dwarf.json /usr/local/share/cephtrace/
