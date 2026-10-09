FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils \
        binutils-aarch64-linux-gnu \
        bison \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        flex \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        git \
        glslang-tools \
        jq \
        ninja-build \
        openjdk-17-jdk-headless \
        patch \
        pkg-config \
        proot \
        python3 \
        python3-pip \
        python3-venv \
        qemu-user-static \
        tar \
        unzip \
        xz-utils \
        zip \
        zstd \
    && python3 -m venv /opt/turnip-venv \
    && /opt/turnip-venv/bin/pip install --no-cache-dir \
        'meson==1.5.2' \
        'mako==1.3.12' \
        'pyyaml==6.0.2' \
        'packaging==24.2' \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /src

ENV PATH="/opt/turnip-venv/bin:${PATH}"

WORKDIR /src
