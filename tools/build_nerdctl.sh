#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v nerdctl >/dev/null 2>&1; then
    echo "nerdctl is required." >&2
    exit 1
fi

build_variant=${DROIDDECK_BUILD_VARIANT:-release}
case "$build_variant" in
    debug|release) ;;
    *) echo "DROIDDECK_BUILD_VARIANT must be debug or release" >&2; exit 1 ;;
esac

export DROIDDECK_CONTAINER_ENGINE=nerdctl
"${repo_root}/tools/build_local.sh"

apk="${repo_root}/app/build/outputs/apk/${build_variant}/app-${build_variant}.apk"
if [[ ! -s "${apk}" ]]; then
    echo "Expected APK was not produced: ${apk}" >&2
    exit 1
fi

destination="${repo_root}/DroidDeck-${build_variant}.apk"
cp -p "${apk}" "${destination}"
printf 'APK copied to: %s\n' "${destination}"
image_name=${DROIDDECK_BUILD_IMAGE:-droiddeck-local-cross:gradle-8.10.2-v5}
nerdctl run --rm --platform linux/amd64 -v "${repo_root}:/src:ro" "${image_name}" \
    sha256sum "/src/DroidDeck-${build_variant}.apk"
