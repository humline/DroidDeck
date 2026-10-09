FROM gradle:8.10.2-jdk17-jammy

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk

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
    && mkdir -p "${ANDROID_HOME}/cmdline-tools" /tmp/android-cmdline-tools \
    && curl -fsSL --retry 3 \
        -o /tmp/android-commandlinetools.zip \
        https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && echo 'f1d671b868cf366b48c67830e13d480db6c249a7dd9b750f0a55b99d24fb1b2b  /tmp/android-commandlinetools.zip' | sha256sum -c - \
    && unzip -q /tmp/android-commandlinetools.zip -d /tmp/android-cmdline-tools \
    && mv /tmp/android-cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null \
    && "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "cmake;3.22.1" \
        "ndk;27.3.13750724" \
    && rm -rf /tmp/android-cmdline-tools /tmp/android-commandlinetools.zip /var/lib/apt/lists/* \
    && mkdir -p /src

ENV PATH="/opt/turnip-venv/bin:${PATH}"

WORKDIR /src
