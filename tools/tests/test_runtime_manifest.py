import hashlib
import importlib.util
import json
import os
import tempfile
import unittest


SCRIPT = os.path.join(os.path.dirname(__file__), "..", "linuxfs", "create_runtime_manifest.py")
SPEC = importlib.util.spec_from_file_location("create_runtime_manifest", SCRIPT)
MANIFEST = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MANIFEST)


class RuntimeManifestTest(unittest.TestCase):
    def test_manifest_records_archive_and_build_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = os.path.join(temporary, "runtime.tar.zst")
            inventory = os.path.join(temporary, "inventory.json")
            with open(archive, "wb") as output:
                output.write(b"runtime-archive")
            with open(inventory, "w", encoding="utf-8") as output:
                json.dump({
                    "packages": [{"name": "sample", "version": "1.0-1"}],
                    "files": [
                        {"path": "usr/bin/sample"},
                        {
                            "path": "usr/lib/libvulkan_freedreno.so",
                            "type": "symlink",
                            "target": "libvulkan_freedreno.so.26",
                        },
                        {
                            "path": "usr/lib/libvulkan_freedreno.so.26",
                            "type": "file",
                            "sha256": "a" * 64,
                        },
                    ],
                }, output)

            metadata, package_list = MANIFEST.create_outputs(
                archive,
                inventory,
                "0e1a71016d7f1b986bfdc31a7be432b56b7f22fd",
                "source-build",
                "93d2ea6927841b042230ed3f841cfc32572a67d9",
                "9ce7a2ef35ae1ab06e024860a0f247962ab11b95",
                "b" * 64,
                "https://example.invalid/turnip.zip",
                "e567b148a9fc4cacaca2783ff12e2baa9b03e6520be305f8d54edc10455f1e3e",
            )

        self.assertEqual(hashlib.sha256(b"runtime-archive").hexdigest(), metadata["sha256"])
        self.assertEqual(len(b"runtime-archive"), metadata["size"])
        self.assertEqual(
            f"runtime-{metadata['sha256'][:16]}",
            metadata["version"],
        )
        self.assertEqual("sample 1.0-1\n", package_list)
        self.assertEqual("source-build", metadata["turnip"]["buildMode"])
        self.assertEqual("93d2ea6927841b042230ed3f841cfc32572a67d9", metadata["turnip"]["builderCommit"])
        self.assertEqual("9ce7a2ef35ae1ab06e024860a0f247962ab11b95", metadata["turnip"]["mesaCommit"])
        self.assertEqual("a" * 64, metadata["turnip"]["installedIcdSha256"])
        self.assertEqual("https://example.invalid/turnip.zip", metadata["turnip"]["fallbackRelease"]["url"])
        self.assertEqual("no pinned digest in upstream builder", metadata["inputs"][0]["verification"])

    def test_manifest_requires_complete_package_and_file_inventory(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = os.path.join(temporary, "runtime.tar.zst")
            inventory = os.path.join(temporary, "inventory.json")
            with open(archive, "wb") as output:
                output.write(b"runtime-archive")
            with open(inventory, "w", encoding="utf-8") as output:
                json.dump({"packages": [], "files": []}, output)
            with self.assertRaisesRegex(ValueError, "must contain packages"):
                MANIFEST.create_outputs(
                    archive,
                    inventory,
                    "0e1a71016d7f1b986bfdc31a7be432b56b7f22fd",
                    "source-build",
                    "93d2ea6927841b042230ed3f841cfc32572a67d9",
                    "9ce7a2ef35ae1ab06e024860a0f247962ab11b95",
                    "b" * 64,
                    "https://example.invalid/turnip.zip",
                    "e567b148a9fc4cacaca2783ff12e2baa9b03e6520be305f8d54edc10455f1e3e",
                )

    def test_fallback_requires_the_pinned_developer_release_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = os.path.join(temporary, "runtime.tar.zst")
            inventory = os.path.join(temporary, "inventory.json")
            with open(archive, "wb") as output:
                output.write(b"runtime-archive")
            with open(inventory, "w", encoding="utf-8") as output:
                json.dump({
                    "packages": [{"name": "sample", "version": "1.0-1"}],
                    "files": [
                        {"path": "usr/lib/libvulkan_freedreno.so", "type": "file", "sha256": "a" * 64},
                    ],
                }, output)
            with self.assertRaisesRegex(ValueError, "does not match the pinned developer release"):
                MANIFEST.create_outputs(
                    archive,
                    inventory,
                    "0e1a71016d7f1b986bfdc31a7be432b56b7f22fd",
                    "developer-release-fallback",
                    "93d2ea6927841b042230ed3f841cfc32572a67d9",
                    "9ce7a2ef35ae1ab06e024860a0f247962ab11b95",
                    "b" * 64,
                    "https://example.invalid/turnip.zip",
                    "e567b148a9fc4cacaca2783ff12e2baa9b03e6520be305f8d54edc10455f1e3e",
                )

    def test_fallback_accepts_the_pinned_developer_release_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = os.path.join(temporary, "runtime.tar.zst")
            inventory = os.path.join(temporary, "inventory.json")
            with open(archive, "wb") as output:
                output.write(b"runtime-archive")
            with open(inventory, "w", encoding="utf-8") as output:
                json.dump({
                    "packages": [{"name": "sample", "version": "1.0-1"}],
                    "files": [
                        {"path": "usr/lib/libvulkan_freedreno.so", "type": "file", "sha256": "a" * 64},
                    ],
                }, output)
            release_hash = "e567b148a9fc4cacaca2783ff12e2baa9b03e6520be305f8d54edc10455f1e3e"
            metadata, _ = MANIFEST.create_outputs(
                archive,
                inventory,
                "0e1a71016d7f1b986bfdc31a7be432b56b7f22fd",
                "developer-release-fallback",
                "93d2ea6927841b042230ed3f841cfc32572a67d9",
                "9ce7a2ef35ae1ab06e024860a0f247962ab11b95",
                release_hash,
                "https://example.invalid/turnip.zip",
                release_hash,
            )
        self.assertEqual("developer-release-fallback", metadata["turnip"]["buildMode"])
        self.assertEqual(release_hash, metadata["turnip"]["inputZipSha256"])

    def test_manifest_rejects_bad_mode_and_missing_turnip_icd(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = os.path.join(temporary, "runtime.tar.zst")
            inventory = os.path.join(temporary, "inventory.json")
            with open(archive, "wb") as output:
                output.write(b"runtime-archive")
            with open(inventory, "w", encoding="utf-8") as output:
                json.dump({
                    "packages": [{"name": "sample", "version": "1.0-1"}],
                    "files": [{"path": "usr/bin/sample", "type": "file", "sha256": "a" * 64}],
                }, output)
            args = (
                archive,
                inventory,
                "0e1a71016d7f1b986bfdc31a7be432b56b7f22fd",
                "source-build",
                "93d2ea6927841b042230ed3f841cfc32572a67d9",
                "9ce7a2ef35ae1ab06e024860a0f247962ab11b95",
                "b" * 64,
                "https://example.invalid/turnip.zip",
                "e567b148a9fc4cacaca2783ff12e2baa9b03e6520be305f8d54edc10455f1e3e",
            )
            with self.assertRaisesRegex(ValueError, "build mode must be"):
                MANIFEST.create_outputs(*args[:3], "invalid", *args[4:])
            with self.assertRaisesRegex(ValueError, "missing the installed Turnip ICD hash"):
                MANIFEST.create_outputs(*args)
            with self.assertRaisesRegex(ValueError, "source commit must be"):
                MANIFEST.create_outputs(*args[:2], "invalid", *args[3:])
            with self.assertRaisesRegex(ValueError, "input SHA-256 must be"):
                MANIFEST.create_outputs(*args[:6], "invalid", *args[7:])


if __name__ == "__main__":
    unittest.main()
