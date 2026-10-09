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
    && (verified=0; for attempt in 1 2 3; do \
        rm -f /tmp/cmdline-tools.zip; \
        curl -fsSL --retry 3 --retry-all-errors \
            -o /tmp/cmdline-tools.zip \
            https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip || true; \
        if [ -s /tmp/cmdline-tools.zip ] \
            && echo '2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258  /tmp/cmdline-tools.zip' | sha256sum -c -; then \
            verified=1; break; \
        elif [ -s /tmp/cmdline-tools.zip ]; then \
            actual=$(sha256sum /tmp/cmdline-tools.zip | cut -d ' ' -f 1); \
            size=$(wc -c < /tmp/cmdline-tools.zip); \
            echo "Android SDK tools archive checksum mismatch on attempt ${attempt}/3 (expected 2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258, got ${actual}, ${size} bytes)." >&2; \
        else \
            echo "Android SDK tools download failed on attempt ${attempt}/3; no archive was received from dl.google.com." >&2; \
        fi; \
        sleep "${attempt}"; \
    done; test "${verified}" = 1) \
    && unzip -tq /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/android-cmdline-tools \
    && mv /tmp/android-cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null \
    && "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "cmake;3.22.1" \
        "ndk;27.3.13750724" \
    && rm -rf /tmp/android-cmdline-tools /tmp/cmdline-tools.zip /var/lib/apt/lists/* \
    && mkdir -p /src

ENV PATH="/opt/turnip-venv/bin:${PATH}"

WORKDIR /src
