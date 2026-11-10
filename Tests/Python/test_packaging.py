"""Guard against shipping a simulator binary or leaking provisioning material."""
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from package_ipa import inspect_device_executable, package


def executable(platform=2, cpu=0x0100000C):
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
    return header + struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)


class DeviceIPATests(unittest.TestCase):
    def test_rejects_simulator_even_when_cpu_is_arm64(self):
        with self.assertRaisesRegex(ValueError, "simulator"):
            inspect_device_executable(executable(platform=7))

    def test_rejects_non_arm64_and_non_macho(self):
        with self.assertRaisesRegex(ValueError, "arm64"):
            inspect_device_executable(executable(cpu=0x01000007))
        with self.assertRaises(ValueError):
            inspect_device_executable(b"this is not an app")

    def test_packages_payload_and_checksum_without_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "RCView.app"
            app.mkdir()
            (app / "RCView").write_bytes(executable())
            (app / "RCView").chmod(0o755)
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "RCView", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
            }))
            output = root / "dist"
            ipa = package(app, output)
            with zipfile.ZipFile(ipa) as archive:
                self.assertEqual(set(archive.namelist()), {"Payload/RCView.app/RCView", "Payload/RCView.app/Info.plist"})
            self.assertIn(ipa.name, (output / "SHA256SUMS.txt").read_text())
            (app / "embedded.mobileprovision").write_bytes(b"private profile")
            with self.assertRaisesRegex(ValueError, "provisioning"):
                package(app, output)


if __name__ == "__main__":
    unittest.main()
