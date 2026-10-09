import importlib.util
import os
import tempfile
import unittest


SCRIPT = os.path.join(os.path.dirname(__file__), "..", "linuxfs", "audit_runtime.py")
SPEC = importlib.util.spec_from_file_location("audit_runtime", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class RuntimeAuditTest(unittest.TestCase):
    def make_root(self, directory):
        database = os.path.join(directory, "var", "lib", "pacman", "local", "sample-1.0-1")
        os.makedirs(database)
        with open(os.path.join(database, "desc"), "w", encoding="utf-8") as output:
            output.write("%NAME%\nsample\n\n%VERSION%\n1.0-1\n\n%DESC%\nTest package\n\n%URL%\nhttps://example.invalid/sample\n\n%LICENSE%\nMIT\n")
        with open(os.path.join(database, "files"), "w", encoding="utf-8") as output:
            output.write("%FILES%\nusr/bin/sample\n")
        binary = os.path.join(directory, "usr", "bin", "sample")
        os.makedirs(os.path.dirname(binary))
        with open(binary, "wb") as output:
            output.write(b"runtime-tool")
        os.chmod(binary, 0o755)
        return directory

    def test_inventory_lists_package_project_and_hashes_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_root(temporary)
            packages = AUDIT.package_inventory(root)
            files = AUDIT.file_inventory(root)
        self.assertEqual(packages[0]["projectUrl"], "https://example.invalid/sample")
        executable = next(item for item in files if item["path"] == "usr/bin/sample")
        self.assertEqual(executable["sha256"], "d330dd92bc62049e201af7a22c59de61ffb5c9846560aed9cdec65fa1e303c6e")

    def test_inventory_rejects_ssh_private_data_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_root(temporary)
            key = os.path.join(root, "root", ".ssh", "id_ed25519")
            os.makedirs(os.path.dirname(key))
            with open(key, "w", encoding="utf-8") as output:
                output.write("not a real key")
            with self.assertRaisesRegex(SystemExit, "Potential private/user data"):
                AUDIT.file_inventory(root)


if __name__ == "__main__":
    unittest.main()
