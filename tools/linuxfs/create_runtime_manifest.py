#!/usr/bin/env python3
"""Write provenance metadata and a package list for a built Linux runtime."""

import argparse
import hashlib
import json
import os
import re


def create_outputs(archive_path, inventory_path, source_commit, turnip_build_mode,
                   turnip_builder_commit, turnip_mesa_commit, turnip_input_sha256,
                   turnip_fallback_url, turnip_fallback_sha256):
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise ValueError("builder source commit must be a full lowercase SHA-1")
    if turnip_build_mode not in ("source-build", "developer-release-fallback"):
        raise ValueError("Turnip build mode must be source-build or developer-release-fallback")
    if not re.fullmatch(r"[0-9a-f]{40}", turnip_builder_commit):
        raise ValueError("Turnip builder commit must be a full lowercase SHA-1")
    if not re.fullmatch(r"[0-9a-f]{40}", turnip_mesa_commit):
        raise ValueError("Turnip Mesa commit must be a full lowercase SHA-1")
    if not re.fullmatch(r"[0-9a-f]{64}", turnip_input_sha256):
        raise ValueError("Turnip input SHA-256 must be 64 lowercase hexadecimal characters")
    if not re.fullmatch(r"[0-9a-f]{64}", turnip_fallback_sha256):
        raise ValueError("Turnip fallback SHA-256 must be 64 lowercase hexadecimal characters")
    if (
        turnip_build_mode == "developer-release-fallback"
        and turnip_input_sha256 != turnip_fallback_sha256
    ):
        raise ValueError("fallback Turnip ZIP hash does not match the pinned developer release")

    with open(inventory_path, encoding="utf-8") as source:
        inventory = json.load(source)
    packages = inventory.get("packages", [])
    if not packages or not inventory.get("files"):
        raise ValueError("runtime inventory must contain packages and filesystem entries")

    digest = hashlib.sha256()
    size = 0
    with open(archive_path, "rb") as archive:
        for block in iter(lambda: archive.read(1 << 20), b""):
            digest.update(block)
            size += len(block)
    archive_sha256 = digest.hexdigest()
    turnip_file = next(
        (item for item in inventory["files"]
         if item.get("path") == "usr/lib/libvulkan_freedreno.so" and item.get("type") == "file"),
        None,
    )
    if not turnip_file or not turnip_file.get("sha256"):
        raise ValueError("runtime inventory is missing the installed Turnip ICD hash")
    metadata = {
        "version": f"runtime-{archive_sha256[:16]}",
        "builder": "The412Banner/winlator-contents",
        "sourceCommit": source_commit,
        "sha256": archive_sha256,
        "size": size,
        "turnip": {
            "repository": "https://github.com/The412Banner/Banners-Turnip",
            "buildMode": turnip_build_mode,
            "builderCommit": turnip_builder_commit,
            "mesaRepository": "https://gitlab.freedesktop.org/mesa/mesa",
            "mesaCommit": turnip_mesa_commit,
            "inputZipSha256": turnip_input_sha256,
            "installedIcdSha256": turnip_file["sha256"],
            "fallbackRelease": {
                "url": turnip_fallback_url,
                "sha256": turnip_fallback_sha256,
            },
        },
        "archive": {"sha256": archive_sha256, "size": size},
        "inputs": [
            {
                "name": "Arch Linux ARM base rootfs",
                "url": "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz",
                "verification": "no pinned digest in upstream builder",
            },
            {
                "name": "Arch Linux ARM packages",
                "url": "http://mirror.archlinuxarm.org/aarch64",
                "verification": "live repository; packages selected by dependency closure",
            },
            {
                "name": "GTK2 Debian package",
                "url": "http://deb.debian.org/debian/pool/main/g/gtk+2.0/libgtk2.0-0t64_2.24.33-7_arm64.deb",
                "sha256": "28b2f1622197443f07f25a93e03db1a964184946ac12f501b8221c895026d0ca",
            },
            {
                "name": "Nettle Debian package",
                "url": "https://deb.debian.org/debian/pool/main/n/nettle/libnettle8_3.8.1-2_arm64.deb",
                "sha256": "c945ff210df69cf7b95e935b8fa936e81c1c1f475355e3d5db83510b174f0cd6",
            },
            {
                "name": "Theora Ubuntu package",
                "url": "http://ports.ubuntu.com/ubuntu-ports/pool/main/libt/libtheora/libtheora0_1.1.1+dfsg.1-16.1build3_arm64.deb",
                "sha256": "78ebaa1c851465dac9e13532623a4e41d28ed55f3df0353daf7c29d96a2e2b87",
            },
            {
                "name": "VPX Ubuntu package",
                "url": "http://ports.ubuntu.com/ubuntu-ports/pool/main/libv/libvpx/libvpx9_1.14.0-1ubuntu2_arm64.deb",
                "sha256": "809bf0d9435520793838a99072ca365ab23956def3583c3b8b4e253135d8e9f4",
            },
            {
                "name": "PRoot",
                "source": "https://github.com/termux/proot/tree/v5.1.107.92",
                "verification": "upstream builder copies prebuilt Termux binaries; its README documents this provenance",
            },
        ],
        "turnipProject": "https://github.com/The412Banner/Banners-Turnip",
    }
    package_list = "".join(
        f"{package['name']} {package['version']}\n" for package in packages
    )
    return metadata, package_list


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("inventory")
    parser.add_argument("manifest")
    parser.add_argument("package_list")
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--turnip-build-mode", required=True)
    parser.add_argument("--turnip-builder-commit", required=True)
    parser.add_argument("--turnip-mesa-commit", required=True)
    parser.add_argument("--turnip-input-sha256", required=True)
    parser.add_argument("--turnip-fallback-url", required=True)
    parser.add_argument("--turnip-fallback-sha256", required=True)
    args = parser.parse_args()
    metadata, package_list = create_outputs(
        args.archive,
        args.inventory,
        args.source_commit,
        args.turnip_build_mode,
        args.turnip_builder_commit,
        args.turnip_mesa_commit,
        args.turnip_input_sha256,
        args.turnip_fallback_url,
        args.turnip_fallback_sha256,
    )
    os.makedirs(os.path.dirname(os.path.abspath(args.manifest)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.package_list)), exist_ok=True)
    with open(args.manifest, "w", encoding="utf-8") as output:
        json.dump(metadata, output, ensure_ascii=False, separators=(",", ":"))
        output.write("\n")
    with open(args.package_list, "w", encoding="utf-8") as output:
        output.write(package_list)
    print(f"Wrote runtime manifest and {len(package_list.splitlines())} package versions.")


if __name__ == "__main__":
    main()
