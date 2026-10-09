#!/usr/bin/env python3
"""Create an inspectable inventory for a built Linux runtime rootfs."""

import hashlib
import json
import os
import stat
import sys


def fields(path):
    result = {}
    current = None
    if not os.path.isfile(path):
        return result
    with open(path, encoding="utf-8", errors="replace") as source:
        for raw in source:
            line = raw.rstrip("\n")
            if line.startswith("%") and line.endswith("%"):
                current = line.strip("%")
                result[current] = []
            elif current and line:
                result[current].append(line)
    return result


def text_value(data, key):
    return (data.get(key) or [""])[0]


def package_inventory(root):
    database = os.path.join(root, "var/lib/pacman/local")
    packages = []
    if not os.path.isdir(database):
        raise SystemExit(f"Missing Arch package database: {database}")
    for dirname in sorted(os.listdir(database)):
        directory = os.path.join(database, dirname)
        if not os.path.isdir(directory):
            continue
        desc = fields(os.path.join(directory, "desc"))
        packages.append({
            "name": text_value(desc, "NAME"),
            "version": text_value(desc, "VERSION"),
            "description": text_value(desc, "DESC"),
            "packageRepository": "Arch Linux ARM (core/extra/alarm)",
            "projectUrl": text_value(desc, "URL") or None,
            "licenses": desc.get("LICENSE", []),
            "installedFiles": fields(os.path.join(directory, "files")).get("FILES", []),
        })
    return packages


def likely_sensitive(path):
    name = path.lower()
    return (
        "/.ssh/" in name
        or name.endswith("/authorized_keys")
        or name.endswith("/known_hosts")
        or name.endswith("/.bash_history")
        or ("/ssh_host_" in name and not name.endswith(".pub"))
        or name.endswith(("/id_rsa", "/id_ed25519", "/id_ecdsa"))
        or name.endswith((".p12", ".pfx", ".jks", ".keystore"))
    )


def file_inventory(root):
    entries = []
    sensitive = []
    for current, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            full = os.path.join(current, name)
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            info = os.lstat(full)
            mode = stat.S_IMODE(info.st_mode)
            if stat.S_ISLNK(info.st_mode):
                entry = {"path": relative, "type": "symlink", "mode": oct(mode), "target": os.readlink(full)}
            elif stat.S_ISDIR(info.st_mode):
                entry = {"path": relative, "type": "directory", "mode": oct(mode)}
            elif stat.S_ISREG(info.st_mode):
                entry = {"path": relative, "type": "file", "mode": oct(mode), "size": info.st_size}
                digest = hashlib.sha256()
                with open(full, "rb") as content:
                    for block in iter(lambda: content.read(1 << 20), b""):
                        digest.update(block)
                entry["sha256"] = digest.hexdigest()
            else:
                entry = {"path": relative, "type": "special", "mode": oct(mode)}
            entries.append(entry)
            if likely_sensitive("/" + relative):
                sensitive.append(relative)
    if sensitive:
        raise SystemExit("Potential private/user data included in runtime: " + ", ".join(sensitive[:20]))
    return entries


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: audit_runtime.py ROOTFS OUTPUT.json")
    root = os.path.abspath(sys.argv[1])
    output = os.path.abspath(sys.argv[2])
    packages = package_inventory(root)
    files = file_inventory(root)
    report = {
        "schemaVersion": 1,
        "description": "Build-time inventory; package project URLs are upstream metadata, not a malware verdict.",
        "packageRepository": "Arch Linux ARM (core/extra/alarm), packages downloaded from mirror.archlinuxarm.org",
        "auxiliaryPackageRepositories": [
            "Debian: libgtk2.0-0t64",
            "Debian: libnettle8",
            "Ubuntu ports: libtheora0 and libvpx9",
        ],
        "packageCount": len(packages),
        "fileCount": len(files),
        "packages": packages,
        "files": files,
    }
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "w", encoding="utf-8") as destination:
        json.dump(report, destination, ensure_ascii=False, separators=(",", ":"))
        destination.write("\n")
    print(f"Audited {len(packages)} packages and {len(files)} filesystem entries.")


if __name__ == "__main__":
    main()
