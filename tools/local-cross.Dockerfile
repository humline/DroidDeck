FROM gradle:8.10.2-jdk17-jammy

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ARG ANDROID_CMDLINE_TOOLS_SHA256=2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
ARG GLSLANG_VERSION=14.3.0
ARG GLSLANG_SHA256=be6339048e20280938d9cb399fcdd06e04f8654d43e170e8cce5a56c9a754284

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
        jq \
        libexpat1-dev \
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
            && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c -; then \
            verified=1; break; \
        elif [ -s /tmp/cmdline-tools.zip ]; then \
            actual=$(sha256sum /tmp/cmdline-tools.zip | cut -d ' ' -f 1); \
            size=$(wc -c < /tmp/cmdline-tools.zip); \
            echo "Android SDK tools archive checksum mismatch on attempt ${attempt}/3 (expected ${ANDROID_CMDLINE_TOOLS_SHA256}, got ${actual}, ${size} bytes)." >&2; \
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

# Mesa's Turnip build compiles its BVH shader preambles with glslang and requires >= 12.2, which is
# also the version the turnip builder's ubuntu-24.04 CI gets from apt. Jammy's glslang-tools is
# 11.x, so build the pinned release from a SHA-256-verified source archive. The last step checks
# the result with Mesa's own version parsing, the gate the Turnip source build runs against.
RUN curl -fsSL --retry 3 --retry-all-errors \
        -o /tmp/glslang.tar.gz \
        "https://github.com/KhronosGroup/glslang/archive/refs/tags/${GLSLANG_VERSION}.tar.gz" \
    && echo "${GLSLANG_SHA256}  /tmp/glslang.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/glslang.tar.gz -C /tmp \
    && cmake -S "/tmp/glslang-${GLSLANG_VERSION}" -B /tmp/glslang-build \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_OPT=OFF \
        -DGLSLANG_TESTS=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --build /tmp/glslang-build \
    && cmake --install /tmp/glslang-build \
    && rm -rf /tmp/glslang.tar.gz "/tmp/glslang-${GLSLANG_VERSION}" /tmp/glslang-build \
    && /opt/turnip-venv/bin/python3 -c "import subprocess; from mesonbuild.mesonlib import version_compare; version = subprocess.check_output(['glslangValidator', '--version'], text=True).split(':')[2]; assert version_compare(version, '>= 12.2'), repr(version); print('glslang', version.splitlines()[0], 'passes Mesa\'s Turnip gate')"

# The pinned Mesa sources declare std::unordered_map with a forward-declared value type in
# tu_autotune.h, which the jammy default aarch64 cross g++ 11 rejects; upstream's turnip builder
# compiles them with ubuntu-24.04's g++ 13. The g++-12 series compiles them, so make it the
# aarch64-linux-gnu-{gcc,g++} the turnip build resolves via PATH, and verify the major version.
# gawk is installed here too: proot's build generates loader-info.c with an awk script that needs
# strtonum, which Ubuntu's default awk (mawk) does not have.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc-12-aarch64-linux-gnu \
        g++-12-aarch64-linux-gnu \
        gawk \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/aarch64-linux-gnu-gcc-12 /usr/local/bin/aarch64-linux-gnu-gcc \
    && ln -sf /usr/bin/aarch64-linux-gnu-g++-12 /usr/local/bin/aarch64-linux-gnu-g++ \
    && aarch64-linux-gnu-g++ --version | head -1 \
    && /opt/turnip-venv/bin/python3 -c "import subprocess; version = subprocess.check_output(['aarch64-linux-gnu-g++', '-dumpversion'], text=True).strip(); assert int(version.split('.')[0]) >= 12, repr(version); print('aarch64 cross g++', version, 'passes the pinned Mesa sources')" \
    && awk 'BEGIN{if (strtonum("0x10") != 16) exit 1}' \
    && echo 'awk has strtonum (gawk) for the proot build'

ENV PATH="/opt/turnip-venv/bin:${PATH}"

WORKDIR /src
