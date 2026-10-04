"""Exercise packaging failures without building, signing or altering real artifacts."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent / "package-app.sh"


class PackagingSafetyTests(unittest.TestCase):
    def fixture(self, root, swift_status, helper_status):
        (root / "scripts").mkdir()
        shutil.copy2(SOURCE, root / "scripts" / "package-app.sh")
        app = root / "dist" / "Vaulty.app"
        app.mkdir(parents=True)
        (app / "previous.txt").write_text("previous verified artifact")
        (root / "dist" / "unrelated.txt").write_text("unrelated output")
        (root / "dist" / "Vaulty-macOS.zip").write_bytes(b"previous archive")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        swift = bin_dir / "swift"
        swift.write_text("#!/bin/sh\nexit " + str(swift_status) + "\n")
        swift.chmod(0o755)
        release = root / ".build" / "release"
        release.mkdir(parents=True)
        for name, status in [("vaulty-app", 0), ("vaulty", helper_status)]:
            executable = release / name
            executable.write_text("#!/bin/sh\nexit " + str(status) + "\n")
            executable.chmod(0o755)
        for folder in ["AppResources", "BrowserExtension", "Brand", "ResearchAgent"]:
            (root / folder).mkdir()
        (root / "AppResources" / "Info.plist").write_text("unused fixture")
        (root / "AppResources" / "Vaulty.icns").write_bytes(b"unused fixture")
        (root / "ResearchAgent" / "recommend.py").write_text("raise SystemExit(0)\n")
        environment = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"))
        return environment

    def assert_preserved(self, root):
        self.assertEqual((root / "dist" / "Vaulty.app" / "previous.txt").read_text(), "previous verified artifact")
        self.assertEqual((root / "dist" / "unrelated.txt").read_text(), "unrelated output")
        self.assertEqual((root / "dist" / "Vaulty-macOS.zip").read_bytes(), b"previous archive")
        self.assertFalse(list((root / "dist").glob(".vaulty-package.*")))

    def test_failed_build_preserves_previous_artifacts(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            environment = self.fixture(root, swift_status=42, helper_status=0)
            result = subprocess.run(["/bin/bash", str(root / "scripts" / "package-app.sh")],
                                    env=environment, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 42)
            self.assert_preserved(root)

    def test_failed_staged_validation_preserves_previous_artifacts(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            environment = self.fixture(root, swift_status=0, helper_status=43)
            result = subprocess.run(["/bin/bash", str(root / "scripts" / "package-app.sh")],
                                    env=environment, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 43, result.stderr)
            self.assert_preserved(root)


if __name__ == "__main__":
    unittest.main()
