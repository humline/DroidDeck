#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if tree_status=$(git -C "${repo_root}" status --porcelain 2>/dev/null); then
    if [[ -n "${tree_status}" ]]; then
        export DROIDDECK_BUILD_TREE_STATE=dirty
    else
        export DROIDDECK_BUILD_TREE_STATE=clean
    fi
else
    export DROIDDECK_BUILD_TREE_STATE=unknown
fi
image_name=${DROIDDECK_BUILD_IMAGE:-droiddeck-local-cross:gradle-8.10.2-v5}
container_engine=${DROIDDECK_CONTAINER_ENGINE:-nerdctl}
case "${container_engine}" in
    nerdctl|docker) ;;
    *)
        echo "DROIDDECK_CONTAINER_ENGINE must be nerdctl or docker." >&2
        exit 1
        ;;
esac
if ! command -v "${container_engine}" >/dev/null 2>&1; then
    echo "${container_engine} is required to build DroidDeck." >&2
    exit 1
fi
sdk_dir=/opt/android-sdk
build_variant=${DROIDDECK_BUILD_VARIANT:-release}
case "$build_variant" in
    debug) gradle_task=assembleDebug ;;
    release) gradle_task=assembleRelease ;;
    *) echo "DROIDDECK_BUILD_VARIANT must be debug or release" >&2; exit 1 ;;
esac

ndk_version=${DROIDDECK_NDK_VERSION:-}
if [[ -z "${ndk_version}" ]]; then
    ndk_version=27.3.13750724
fi
if [[ "${ndk_version}" != 27.3.13750724 ]]; then
    echo "The build image contains NDK 27.3.13750724; rebuild the image to use another DROIDDECK_NDK_VERSION." >&2
    exit 1
fi
export ANDROID_HOME="${sdk_dir}"
export ANDROID_SDK_ROOT="${sdk_dir}"
export NDK="${sdk_dir}/ndk/${ndk_version}"

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/droiddeck-build.XXXXXX")
staging_dir=$(cd "${staging_dir}" && pwd)
bundle_asset="${repo_root}/app/src/main/assets/pulseaudio.tzst"
bundle_backup="${staging_dir}/pulseaudio.original.tzst"
bundle_replaced=0
sync_assets="${repo_root}/app/src/main/assets/droiddeck-esync"
sync_assets_backup="${staging_dir}/droiddeck-esync.original"
sync_assets_preexisting=0
sync_assets_replaced=0
linuxfs_dir="${repo_root}/app/src/main/assets/linuxfs"
linuxfs_backup="${staging_dir}/linuxfs.original"
linuxfs_preexisting=0
linuxfs_replaced=0
cleanup() {
    local exit_code=$?
    trap - EXIT
    if [[ "${bundle_replaced}" == 1 ]]; then
        cp -p "${bundle_backup}" "${bundle_asset}" || exit_code=1
    fi
    if [[ "${linuxfs_replaced}" == 1 ]]; then
        rm -rf -- "${linuxfs_dir}" || exit_code=1
        if [[ "${linuxfs_preexisting}" == 1 ]]; then
            mv "${linuxfs_backup}" "${linuxfs_dir}" || exit_code=1
        fi
    fi
    if [[ "${sync_assets_replaced}" == 1 && "${exit_code}" != 0 ]]; then
        rm -rf -- "${sync_assets}" || exit_code=1
        if [[ "${sync_assets_preexisting}" == 1 ]]; then
            mv "${sync_assets_backup}" "${sync_assets}" || exit_code=1
        fi
    fi
    rm -rf -- "${staging_dir}" || exit_code=1
    exit "${exit_code}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -d "${linuxfs_dir}" ]]; then
    cp -a "${linuxfs_dir}" "${linuxfs_backup}"
    linuxfs_preexisting=1
fi
linuxfs_replaced=1
rm -rf -- "${linuxfs_dir}"
mkdir -p "${linuxfs_dir}"

echo "Building/updating local build image ${image_name}..."
"${container_engine}" build --platform linux/amd64 -t "${image_name}" \
    -f "${repo_root}/tools/local-cross.Dockerfile" "${repo_root}"

cache_dir=${DROIDDECK_BUILD_CACHE:-"${HOME}/.cache/droiddeck-build"}
mkdir -p "${cache_dir}"
cache_dir=$(cd "${cache_dir}" && pwd)
run_build_image() {
    "${container_engine}" run --rm --platform linux/amd64 \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -v "${repo_root}:/src" \
        -v "${cache_dir}:${cache_dir}" \
        -v "${staging_dir}:${staging_dir}" \
        -w /src "${image_name}" "$@"
}
run_build_image bash -lc '
    set -euo pipefail
    for tool in bash curl tar zstd sha256sum unzip python3 git jq readelf gradle \
            gcc g++ make patch meson ninja glslangValidator \
            aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ aarch64-linux-gnu-readelf; do
        command -v "$tool" >/dev/null || {
            echo "Build image is missing required tool: $tool" >&2
            exit 1
        }
    done
    test -x /opt/android-sdk/build-tools/34.0.0/zipalign
    test -x /opt/android-sdk/build-tools/34.0.0/apksigner
    test -x /opt/android-sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang
'

"${container_engine}" run --rm --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    -v "${repo_root}:/src" -w /src "${image_name}" bash -lc '
        set -euo pipefail
        d=app/src/main/assets/linuxfs
        mkdir -p "$d"
        aarch64-linux-gnu-g++ -shared -fPIC -O2 -Wall -Wno-attributes -Wno-nonnull-compare \
            -pthread -std=c++17 -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL \
            -o "$d/libfakeinput.so" app/src/main/cpp/fakeinput_steam.cpp -ldl
        aarch64-linux-gnu-strip --strip-unneeded "$d/libfakeinput.so"
        aarch64-linux-gnu-gcc -shared -fPIC -O2 -Wall -pthread \
            -o "$d/libblsession.so" tools/linuxfs/preload/*.c -ldl
        aarch64-linux-gnu-strip --strip-unneeded "$d/libblsession.so"
        aarch64-linux-gnu-gcc -shared -fPIC -O2 -Wall -pthread \
            -o "$d/libblfastpath.so" tools/proot/fastpath/fastpath.c -ldl
        aarch64-linux-gnu-strip --strip-unneeded "$d/libblfastpath.so"
        mkdir -p "$d/usr/local/bin"
        aarch64-linux-gnu-gcc -O2 -Wall -Wextra -o "$d/usr/local/bin/droiddeck-clipboard" tools/linuxfs/clipboard/clipboard.c -ldl
        aarch64-linux-gnu-strip --strip-unneeded "$d/usr/local/bin/droiddeck-clipboard"
        for script in tools/linuxfs/overlay/usr/local/bin/droiddeck-* tools/linuxfs/overlay/usr/local/bin/steam-compatibility; do
            install -Dm644 "$script" "$d/usr/local/bin/$(basename "$script")"
        done
        for f in tools/linuxfs/overlay/usr/bin/* tools/linuxfs/overlay/usr/bin/steamos-polkit-helpers/*; do
            [ -f "$f" ] && install -Dm644 "$f" "$d/${f#tools/linuxfs/overlay/}"
        done
        install -Dm644 tools/linuxfs/desktop/droiddeck-desktop "$d/usr/local/bin/droiddeck-desktop"
        install -Dm644 tools/linuxfs/desktop/droiddeck-gpu "$d/usr/local/bin/droiddeck-gpu"
        install -Dm644 tools/linuxfs/desktop/droiddeck-desktop-gpu "$d/usr/local/bin/droiddeck-desktop-gpu"
        install -Dm644 tools/linuxfs/desktop/autostart "$d/etc/xdg/labwc/autostart"
        install -Dm644 tools/linuxfs/desktop/rc.xml "$d/etc/xdg/labwc/rc.xml"
        install -Dm644 tools/linuxfs/desktop/panel.conf "$d/etc/xdg/lxqt/panel.conf"
        install -Dm644 tools/linuxfs/desktop/firefox-droiddeck.js \
            "$d/usr/lib/firefox/defaults/pref/droiddeck.js"

        need=$(aarch64-linux-gnu-readelf -d "$d/libfakeinput.so" | sed -n "s/.*NEEDED.*\\[\\(.*\\)\\]/\\1/p")
        for bad in libstdc++.so.6 libgcc_s.so.1; do
            if printf "%s\\n" "$need" | grep -qx "$bad"; then
                echo "libfakeinput.so links $bad; the C++ runtime must stay static" >&2
                exit 1
            fi
        done
        syms() { aarch64-linux-gnu-readelf -Ws "$1" | awk '\''$4 == "FUNC" && $5 == "GLOBAL" {sub(/@.*/, "", $8); print $8}'\''; }
        fake=$(syms "$d/libfakeinput.so")
        for sym in open openat ioctl read close poll ppoll select stat fstat access scandir; do
            printf "%s\\n" "$fake" | grep -qx "$sym" || {
                echo "libfakeinput.so does not export $sym" >&2
                exit 1
            }
        done
        session=$(syms "$d/libblsession.so")
        for sym in socket bind getsockname setsockopt statfs statvfs; do
            printf "%s\\n" "$session" | grep -qx "$sym" || {
                echo "libblsession.so does not export $sym" >&2
                exit 1
            }
        done
        test -f "$d/usr/local/bin/droiddeck-session"
        test -f "$d/usr/local/bin/droiddeck-proton-extra"
    '

"${container_engine}" run --rm --platform linux/amd64 \
    -v "${repo_root}:/src" -w /src debian:bullseye bash -c '
        set -euo pipefail
        printf "deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n" > /etc/apt/sources.list
        apt-get -o Acquire::Check-Valid-Until=false update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends gcc g++ gcc-multilib g++-multilib binutils >/dev/null
        tools/linuxfs/build-x86-preloads.sh app/src/main/assets/linuxfs
        chown -R '"$(id -u):$(id -g)"' app/src/main/assets/linuxfs
    '

# Pinned downloads are kept between builds, named by their checksum, so a rebuild fetches nothing
# it already has. A cached file is checked again before use; a bad one is fetched anew.
# cached <sha256> <name> <command...>: prints the cached path, running the command (which writes
# to "$out") only when the cache has no file with that checksum.
cached() {
    local sha=$1 name=$2 out
    shift 2
    out="${cache_dir}/${sha}-${name}"
    if [[ -f "${out}" ]] \
            && run_build_image bash -c 'printf "%s  %s\n" "$1" "$2" | sha256sum -c -' _ "${sha}" "${out}" >/dev/null 2>&1; then
        echo "${out}"
        return 0
    fi
    rm -f "${out}.part"
    run_build_image env out="${out}.part" "$@" >&2
    run_build_image bash -c 'printf "%s  %s\n" "$1" "$2" | sha256sum -c -' _ "${sha}" "${out}.part" >&2
    mv "${out}.part" "${out}"
    echo "${out}"
}

# The runtime archive and Turnip driver are built locally in the same container image as the
# native preload libraries, then staged as Gradle assets. Persist sources, package downloads and
# build intermediates so subsequent local builds can reuse the expensive upstream work.
runtime_cache="${cache_dir}/linuxfs-runtime"
mkdir -p "${runtime_cache}"
"${container_engine}" run --rm --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    -v "${repo_root}:/src" -v "${runtime_cache}:/runtime-work" \
    -w /src "${image_name}" \
    bash tools/linuxfs/build_runtime_local.sh /runtime-work

if [[ -f "${repo_root}/tools/gamescope/release.env" ]]; then
    . "${repo_root}/tools/gamescope/release.env"
    gamescope_archive=$(cached "${GAMESCOPE_SHA256}" gamescope.tzst \
        bash -c 'curl -fsSL --retry 3 -o "$out" "https://github.com/$1/releases/download/$2/$3"' \
        _ "${GAMESCOPE_REPO}" "${GAMESCOPE_TAG}" gamescope.tzst)
    run_build_image bash -c 'zstd -dc "$1" | tar -xf - -C "$2"' _ "${gamescope_archive}" "${linuxfs_dir}"
    test -f "${linuxfs_dir}/usr/local/bin/gamescope"
fi

if [[ -f "${repo_root}/tools/wlroots/release.env" ]]; then
    . "${repo_root}/tools/wlroots/release.env"
    wlroots_archive=$(cached "${WLROOTS_SHA256}" wlroots.tzst \
        bash -c 'curl -fsSL --retry 3 -o "$out" "https://github.com/$1/releases/download/$2/$3"' \
        _ "${WLROOTS_REPO}" "${WLROOTS_TAG}" wlroots.tzst)
    run_build_image bash -c 'zstd -dc "$1" | tar -xf - -C "$2"' _ "${wlroots_archive}" "${linuxfs_dir}"
    test -f "${linuxfs_dir}/usr/local/lib/droiddeck-wlroots/libwlroots-0.20.so"
fi

. "${repo_root}/tools/linuxfs/uruntime.env"
uruntime_binary=$(cached "${URUNTIME_SHA256}" "${URUNTIME_ASSET}" \
    bash -c 'curl -fsSL --retry 3 -o "$out" "$0"' "https://github.com/VHSgunzo/uruntime/releases/download/${URUNTIME_VERSION}/${URUNTIME_ASSET}")
install -Dm644 "${uruntime_binary}" "${linuxfs_dir}/usr/local/lib/droiddeck/uruntime"
install -Dm644 "${repo_root}/tools/linuxfs/licenses/uruntime-LICENSE" "${linuxfs_dir}/usr/local/share/licenses/uruntime/LICENSE"

if [[ -f "${repo_root}/tools/droiddeck-esync/release.env" ]]; then
    . "${repo_root}/tools/droiddeck-esync/release.env"
    sync_archive=$(cached "${SYNC_BUNDLE_SHA256}" "${SYNC_BUNDLE_ASSET}" \
        bash -c 'curl -fsSL --retry 3 -o "$out" "https://github.com/$1/releases/download/$2/$3"' \
        _ "${SYNC_BUNDLE_REPO}" "${SYNC_BUNDLE_TAG}" "${SYNC_BUNDLE_ASSET}")
    sync_assets_stage="${staging_dir}/droiddeck-esync.new"
    mkdir -p "${sync_assets_stage}"
    run_build_image bash -c 'zstd -dc "$1" | tar -xf - -C "$2"' _ "${sync_archive}" "${sync_assets_stage}"
    test -f "${sync_assets_stage}/index.json"
    test -f "${sync_assets_stage}/index.json.sig"
    if [[ -d "${sync_assets}" ]]; then
        cp -a "${sync_assets}" "${sync_assets_backup}"
        sync_assets_preexisting=1
    fi
    sync_assets_replaced=1
    rm -rf "${sync_assets}"
    mv "${sync_assets_stage}" "${sync_assets}"
    sync_index="${staging_dir}/sync-index.json"
    run_build_image curl -fsSL --retry 3 -o "${sync_index}" \
        "https://github.com/${SYNC_BUNDLE_REPO}/releases/download/${SYNC_BUNDLE_TAG}/index.json"
    revoked=$(run_build_image python3 -c 'import json, sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1]))["packs"] if p.get("revoked") is True))' "${sync_index}")
    for id in ${revoked}; do
        if [[ -e "${sync_assets}/packs/${id}.tzst" ]]; then
            echo "${SYNC_BUNDLE_ASSET} carries revoked pack ${id}; it is left out of the APK" >&2
            rm -f "${sync_assets}/packs/${id}.tzst"
        fi
    done
    rm -f "${sync_index}"
elif [[ -d "${sync_assets}" ]]; then
    echo "No tools/droiddeck-esync/release.env: the APK bundles the droiddeck-esync packs already in ${sync_assets}." >&2
fi

mango_dir="${linuxfs_dir}/usr/local/lib/mangoapp"
mango_pkgs="${staging_dir}/mango-pkgs"
mkdir -p "${mango_dir}" "${mango_pkgs}"
while read -r package_sha256 package_url; do
    [[ -n "${package_url}" ]] || continue
    package_archive=$(cached "${package_sha256}" "$(basename "${package_url}")" \
        bash -c 'curl -fsSL --retry 3 -o "$out" "$0"' "${package_url}")
    run_build_image bash -c 'zstd -dc "$1" | tar -xf - -C "$2"' _ "${package_archive}" "${mango_pkgs}"
done < <(grep -v '^#' "${repo_root}/tools/mangoapp/packages.txt")
install -m644 "${mango_pkgs}/usr/bin/mangoapp" "${mango_dir}/mangoapp"
for library in libfmt.so.10 libspdlog.so.1.13 libglfw.so.3 libtraceevent.so.1; do
    cp -L "${mango_pkgs}/usr/lib/${library}" "${mango_dir}/${library}"
done
# Ours, not the package's: GPU memory without tracefs (tools/mangoapp/libtracefs-shim.c).
"${container_engine}" run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" -v "${repo_root}:/src" -w /src "${image_name}" \
    aarch64-linux-gnu-gcc -shared -fPIC -O2 -Wall -Wl,-soname,libtracefs.so.1 \
    -o app/src/main/assets/linuxfs/usr/local/lib/mangoapp/libtracefs.so.1 tools/mangoapp/libtracefs-shim.c
mkdir -p "${linuxfs_dir}/usr/local/bin"
install -m644 "${repo_root}/tools/mangoapp/mangoapp" "${linuxfs_dir}/usr/local/bin/mangoapp"

pa_source=${DROIDDECK_PA13_SOURCE_DIR:-"${staging_dir}/pulseaudio-13.0"}
if [[ -z "${DROIDDECK_PA13_SOURCE_DIR:-}" ]]; then
    pa_tarball="${cache_dir}/pulseaudio-13.0.tar.gz"
    run_build_image bash -c '
        set -euo pipefail
        archive=$1
        if [[ ! -s "$archive" ]] || ! tar -tzf "$archive" >/dev/null 2>&1; then
            curl -fsSL --retry 3 -o "$archive.part" \
                https://github.com/pulseaudio/pulseaudio/archive/refs/tags/v13.0.tar.gz
            mv "$archive.part" "$archive"
        fi
        mkdir -p "$2"
        tar -xzf "$archive" -C "$2" --strip-components=1
    ' _ "${pa_tarball}" "${pa_source}"
else
    if [[ ! -d "${pa_source}" ]]; then
        echo "PulseAudio source directory does not exist: ${pa_source}" >&2
        exit 1
    fi
    pa_source=$(cd "${pa_source}" && pwd)
fi
if [[ ! -f "${pa_source}/src/pulse/version.h.in" ]]; then
    echo "PulseAudio 13.0 source not found at ${pa_source}; set DROIDDECK_PA13_SOURCE_DIR." >&2
    exit 1
fi

sink_output="${staging_dir}/sink-out"
run_build_image tools/directaudio/fetch.sh "${repo_root}" "${sink_output}"
pa_mount=()
case "${pa_source}" in
    "${repo_root}"/*|"${staging_dir}"/*) ;;
    *) pa_mount=(-v "${pa_source}:${pa_source}:ro") ;;
esac
"${container_engine}" run --rm --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    -v "${repo_root}:/src" -v "${cache_dir}:${cache_dir}" -v "${staging_dir}:${staging_dir}" \
    "${pa_mount[@]}" -w /src "${image_name}" \
    env NDK="/opt/android-sdk/ndk/${ndk_version}" \
    tools/aaudio-sink/build.sh "${pa_source}" "${sink_output}"
# proot is rebuilt only when its sources (source.env, the patches, the build script) changed since
# the libraries in jniLibs were built.
proot_out="${repo_root}/app/src/main/jniLibs/arm64-v8a"
proot_inputs=$(run_build_image bash -c \
    'cd tools/proot && find . -type f ! -name "*.pyc" -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1')
if [[ -f "${proot_out}/libproot.so" && -f "${proot_out}/libproot-loader.so" \
        && "$(cat "${proot_out}/.proot-inputs" 2>/dev/null)" = "${proot_inputs}" ]]; then
    echo "proot: sources unchanged, keeping ${proot_out}/libproot.so"
else
    run_build_image env NDK="${NDK}" tools/proot/build.sh "${proot_out}"
    echo "${proot_inputs}" > "${proot_out}/.proot-inputs"
fi

cp -p "${bundle_asset}" "${bundle_backup}"
bundle_dir="${staging_dir}/pulseaudio-bundle"
mkdir -p "${bundle_dir}"
run_build_image bash -c 'zstd -dc "$1" | tar -xf - -C "$2"' _ "${bundle_asset}" "${bundle_dir}"
if [[ -e "${bundle_dir}/modules/arm64/module-aaudio-sink.so" \
        || -e "${bundle_dir}/modules/arm64/module-directaudio-native-sink.so" ]]; then
    echo "The committed audio bundle already contains a built ARM64 sink." >&2
    exit 1
fi
install -m755 "${sink_output}/module-aaudio-sink.so" \
    "${bundle_dir}/modules/arm64/module-aaudio-sink.so"
install -m755 "${sink_output}/module-directaudio-native-sink.so" \
    "${bundle_dir}/modules/arm64/module-directaudio-native-sink.so"
run_build_image bash -c 'set -euo pipefail; tar -cf - -C "$1" . | zstd -19 -T0 -c > "$2"' _ \
    "${bundle_dir}" "${staging_dir}/pulseaudio.tzst"
bundle_replaced=1
mv "${staging_dir}/pulseaudio.tzst" "${bundle_asset}"

cd "${repo_root}"
gradle_cache="${HOME}/.gradle"
mkdir -p "${gradle_cache}"
"${container_engine}" run --rm --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e GRADLE_USER_HOME=/gradle \
    -e ANDROID_HOME=/opt/android-sdk -e ANDROID_SDK_ROOT=/opt/android-sdk \
    -e NDK="/opt/android-sdk/ndk/${ndk_version}" \
    -v "${repo_root}:/src" -v "${gradle_cache}:/gradle" \
    -w /src "${image_name}" \
    gradle "${gradle_task}" --console=plain -PndkVersion="${ndk_version}"
run_build_image python3 tools/release/check_session_assets.py \
    "app/build/outputs/apk/${build_variant}/app-${build_variant}.apk"
cp -p "${bundle_backup}" "${bundle_asset}"
bundle_replaced=0

apk="${repo_root}/app/build/outputs/apk/${build_variant}/app-${build_variant}.apk"
apk_relative="app/build/outputs/apk/${build_variant}/app-${build_variant}.apk"
audio_check="${staging_dir}/audio-check"
mkdir -p "${audio_check}"
run_build_image bash -c \
    'unzip -p "$1" assets/pulseaudio.tzst | zstd -dc | tar -xf - -C "$2"' _ "${apk}" "${audio_check}"
for audio_file in \
    pactl \
    modules/arm64/module-aaudio-sink.so \
    modules/arm64/module-directaudio-native-sink.so; do
    if [[ ! -f "${audio_check}/${audio_file}" ]]; then
        echo "APK audio bundle is missing ${audio_file}." >&2
        exit 1
    fi
done

"${container_engine}" run --rm --platform linux/amd64 -e build_variant="${build_variant}" -v "${repo_root}:/src:ro" -w /src "${image_name}" \
    bash -lc '
        set -euo pipefail
        apk=app/build/outputs/apk/${build_variant}/app-${build_variant}.apk
        work=$(mktemp -d)
        unzip -q "$apk" "lib/arm64-v8a/*" -d "$work"
        cd "$work/lib/arm64-v8a"
        system="libc.so libm.so libdl.so liblog.so libandroid.so libz.so libvulkan.so libstdc++.so
            libGLESv2.so libEGL.so libnativewindow.so libjnigraphics.so libaaudio.so
            libOpenSLES.so libmediandk.so libcamera2ndk.so libsync.so libneuralnetworks.so"
        fail=0
        for so in *.so; do
            for need in $(readelf -d "$so" | sed -n "s/.*NEEDED.*\\[\\(.*\\)\\]/\\1/p"); do
                [ -f "$need" ] && continue
                case " $(echo $system) " in *" $need "*) continue ;; esac
                echo "missing: $so -> $need"
                fail=1
            done
        done
        [ "$fail" -eq 0 ]
        echo "every NEEDED resolves"
    '

build_tools_version=34.0.0
sdk_tool() {
    local tool=$1
    shift
    run_build_image "/opt/android-sdk/build-tools/${build_tools_version}/${tool}" "$@"
}

sdk_tool zipalign -p -f 4 "${apk_relative}" "${apk_relative}.aligned"
sdk_tool apksigner sign \
    --ks "keystore/testkey.p12" --ks-type PKCS12 --ks-pass pass:android \
    --ks-key-alias testkey --key-pass pass:android \
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
    --out "${apk_relative}" "${apk_relative}.aligned"
rm -f "${apk}.aligned" "${apk}.idsig"

signature_output=$(sdk_tool apksigner verify --min-sdk-version 21 --verbose --print-certs "${apk_relative}")
printf '%s\n' "${signature_output}"
if ! run_build_image unzip -l "${apk}" | grep -E 'META-INF/.*\.(SF|RSA|DSA)$' >/dev/null; then
    echo "APK signature check failed: JAR signature files are missing." >&2
    exit 1
fi
for scheme in \
    'Verified using v1 scheme (JAR signing): true' \
    'Verified using v2 scheme (APK Signature Scheme v2): true' \
    'Verified using v3 scheme (APK Signature Scheme v3): true'; do
    grep -qF "${scheme}" <<<"${signature_output}" || {
        echo "APK signature check failed: ${scheme}" >&2
        exit 1
    }
done
grep -qi 'CN=Android, OU=Android, O=Android' <<<"${signature_output}" || {
    echo "APK signature check failed: the signer is not the AOSP testkey." >&2
    exit 1
}

# With DroidDeck's own key at hand, sign as CI's main builds are (tools/release/sign-apk.sh), so
# the apk installs over a release instead of being refused as a different signer. The key's
# location and password live in an untracked .signing.env (RELEASE_KEYSTORE, RELEASE_STORE_PASSWORD,
# RELEASE_KEY_ALIAS), looked for in this checkout and then in the main one, which worktrees share.
signing_env=${DROIDDECK_SIGNING_ENV:-}
if [[ -z "${signing_env}" ]]; then
    for candidate in "${repo_root}/.signing.env" \
            "$(dirname "$(git -C "${repo_root}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo .)")/.signing.env"; do
        [[ -f "${candidate}" ]] && { signing_env=${candidate}; break; }
    done
fi
if [[ -n "${signing_env}" ]]; then
    echo "Signing with DroidDeck's key (${signing_env})"
    (
        set -a
        # shellcheck disable=SC1090
        . "${signing_env}"
        set +a
        keystore_mount=()
        if [[ -n "${RELEASE_KEYSTORE:-}" ]]; then
            keystore_mount=(-v "${RELEASE_KEYSTORE}:${RELEASE_KEYSTORE}:ro")
        fi
        "${container_engine}" run --rm --platform linux/amd64 \
            --user "$(id -u):$(id -g)" \
            -e HOME=/tmp -e BUILD_TOOLS="/opt/android-sdk/build-tools/${build_tools_version}" \
            -v "${repo_root}:/src" -v "${signing_env}:${signing_env}:ro" \
            "${keystore_mount[@]}" -w /src "${image_name}" \
            bash -lc 'set -a; . "$1"; set +a; tools/release/sign-apk.sh "$2" standard "$3"' \
            bash "${signing_env}" "${apk_relative}" "${apk_relative}.release"
    )
    mv "${apk}.release" "${apk}"
fi

printf 'APK: %s\n' "${apk}"
printf 'SHA-256: '
run_build_image sha256sum "${apk}" | awk '{print $1}'
