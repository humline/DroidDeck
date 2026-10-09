#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work_root=${1:-${DROIDDECK_RUNTIME_WORKDIR:-/runtime-work}}
output_dir="${repo_root}/app/build/generated/linuxfsRuntime"
source "${repo_root}/tools/linuxfs/runtime-build.env"

for value in \
    "${LINUXFS_BUILDER_COMMIT}" \
    "${LINUXFS_TURNIP_BUILDER_COMMIT}" \
    "${LINUXFS_TURNIP_MESA_COMMIT}"; do
    [[ "${value}" =~ ^[0-9a-f]{40}$ ]] || {
        echo "Invalid pinned source commit: ${value}" >&2
        exit 1
    }
done
[[ "${LINUXFS_TURNIP_FALLBACK_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid pinned Turnip fallback SHA-256." >&2
    exit 1
}

mkdir -p "${work_root}"

checkout_pinned() {
    local repository=$1 url=$2 commit=$3
    if [[ ! -d "${repository}/.git" ]]; then
        mkdir -p "$(dirname "${repository}")"
        git clone --no-checkout "${url}" "${repository}"
    fi
    git -C "${repository}" remote set-url origin "${url}"
    git -C "${repository}" fetch --depth=1 origin "${commit}"
    git -C "${repository}" checkout --detach --force FETCH_HEAD
    [[ "$(git -C "${repository}" rev-parse HEAD)" == "${commit}" ]] || {
        echo "Pinned checkout mismatch: ${repository}" >&2
        exit 1
    }
}

turnip_repo="${work_root}/upstream-turnip"
linuxfs_repo="${work_root}/upstream-linuxfs"
checkout_pinned "${turnip_repo}" \
    https://github.com/The412Banner/Banners-Turnip.git \
    "${LINUXFS_TURNIP_BUILDER_COMMIT}"
checkout_pinned "${linuxfs_repo}" \
    https://github.com/The412Banner/winlator-contents.git \
    "${LINUXFS_BUILDER_COMMIT}"

turnip_zip="${work_root}/turnip.zip"
turnip_mode=source-build
turnip_build_dir="${work_root}/turnip-build"
mkdir -p "${turnip_build_dir}"
rm -f "${turnip_build_dir}/linux_workdir/Turnip-DroidDeck-Linux.zip"

echo "Building Linux Turnip from Mesa ${LINUXFS_TURNIP_MESA_COMMIT}..."
build_turnip_from_source() (
    cd "${turnip_build_dir}" || exit 1
    export MESA_COMMIT="${LINUXFS_TURNIP_MESA_COMMIT}"
    export ZIP_NAME=Turnip-DroidDeck-Linux.zip
    export META_NAME="Mesa Turnip DroidDeck Linux"
    export PACKAGE_VERSION=1
    export VARIANT=regular
    if ! "${turnip_repo}/build_turnip_linux.sh"; then
        echo "Turnip source build command failed." >&2
        exit 1
    fi
    python3 "${turnip_repo}/.github/scripts/verify_driver_zip.py" \
        --kind linux \
        --zip "${turnip_build_dir}/linux_workdir/${ZIP_NAME}" \
        --variant regular \
        --expect-name "${META_NAME}" \
        --expect-package-version "${PACKAGE_VERSION}" \
        --build-report "${turnip_build_dir}/linux_workdir/build-report.json" \
        --report "${work_root}/turnip-build-verification.json"
)

if build_turnip_from_source; then
    install -m 644 "${turnip_build_dir}/linux_workdir/Turnip-DroidDeck-Linux.zip" "${turnip_zip}"
else
    echo "Turnip source build/verification failed; trying the pinned developer release." >&2
    turnip_mode=developer-release-fallback
    rm -f "${turnip_zip}.part"
    curl -fsSL --retry 3 -o "${turnip_zip}.part" "${LINUXFS_TURNIP_FALLBACK_URL}"
    printf '%s  %s\n' "${LINUXFS_TURNIP_FALLBACK_SHA256}" "${turnip_zip}.part" | sha256sum -c -
    mv "${turnip_zip}.part" "${turnip_zip}"
fi

unzip -t "${turnip_zip}"
unzip -Z1 "${turnip_zip}" | grep -Fxq libvulkan_freedreno.so
turnip_input_sha256=$(sha256sum "${turnip_zip}" | cut -d' ' -f1)

mkdir -p "${output_dir}"
runtime_archive="${output_dir}/linuxfs-runtime.tar.zst"
runtime_work="${work_root}/linuxfs-work"
export TURNIP_URL="file://${turnip_zip}"
"${linuxfs_repo}/linuxfs/build-base.sh" "${runtime_work}" "${runtime_archive}"

python3 "${repo_root}/tools/linuxfs/audit_runtime.py" \
    "${runtime_work}/rootfs" \
    "${output_dir}/linuxfs-runtime-inventory.json"
python3 "${repo_root}/tools/linuxfs/create_runtime_manifest.py" \
    "${runtime_archive}" \
    "${output_dir}/linuxfs-runtime-inventory.json" \
    "${output_dir}/linuxfs-runtime.json" \
    "${output_dir}/linuxfs-packages.txt" \
    --source-commit "${LINUXFS_BUILDER_COMMIT}" \
    --turnip-build-mode "${turnip_mode}" \
    --turnip-builder-commit "${LINUXFS_TURNIP_BUILDER_COMMIT}" \
    --turnip-mesa-commit "${LINUXFS_TURNIP_MESA_COMMIT}" \
    --turnip-input-sha256 "${turnip_input_sha256}" \
    --turnip-fallback-url "${LINUXFS_TURNIP_FALLBACK_URL}" \
    --turnip-fallback-sha256 "${LINUXFS_TURNIP_FALLBACK_SHA256}"

jq -e '(.sha256 | test("^[0-9a-f]{64}$")) and (.size > 0) and (.sourceCommit | test("^[0-9a-f]{40}$"))' \
    "${output_dir}/linuxfs-runtime.json"
jq -e '.packageCount > 0 and .fileCount > 0' \
    "${output_dir}/linuxfs-runtime-inventory.json"
printf '%s  %s\n' \
    "$(jq -r '.sha256' "${output_dir}/linuxfs-runtime.json")" \
    "${runtime_archive}" | sha256sum -c -
[[ "$(stat -c %s "${runtime_archive}")" == "$(jq -r '.size' "${output_dir}/linuxfs-runtime.json")" ]]
test -s "${output_dir}/linuxfs-packages.txt"

echo "Runtime assets staged for APK build: ${output_dir}"
echo "Turnip build mode: ${turnip_mode}"
