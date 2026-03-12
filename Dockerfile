#syntax=docker/dockerfile:1

FROM alpine:latest AS otto-fetcher

ARG OTTO_VERSION=latest

RUN apk add --no-cache curl && \
    curl -o /tmp/otto https://s3.clyso.com/otto/${OTTO_VERSION}/otto && \
    chmod +x /tmp/otto

FROM alpine:latest AS o8-fetcher

ARG O8_VERSION=latest

RUN apk add --no-cache curl && \
    curl -fsSL -o /tmp/o8 https://s3.clyso.com/o8/${O8_VERSION}/o8 && \
    chmod +x /tmp/o8

ARG CEPH_IMG=quay.io/ceph/ceph
ARG CEPH_TAG=latest

FROM ${CEPH_IMG}:${CEPH_TAG}

COPY --from=otto-fetcher /tmp/otto /usr/local/bin/otto
COPY --from=o8-fetcher /tmp/o8 /usr/local/bin/o8