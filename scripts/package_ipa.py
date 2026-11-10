#!/usr/bin/env python3
"""Package a device .app as an unsigned IPA; preserve binary executable permissions."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def inspect_device_executable(data: bytes) -> None:
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin arm64 Mach-O executable built for a physical iPad.")
    _, cpu, _, _, count, _, _, _ = struct.unpack_from("<8I", data)
    if cpu != 0x0100000C:
        raise ValueError("Executable is not arm64.")
    offset = 32
    platform = None
    for _ in range(count):
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Malformed Mach-O load command.")
        if command == 0x32:
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        offset += size
    if platform != 2:
        raise ValueError(f"Expected platform iOS (2), got {platform}; simulator apps cannot be sideloaded.")


def package(app: Path, destination: Path) -> Path:
    app = app.resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise ValueError(f"Missing application bundle: {app}")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info["CFBundleExecutable"]
    inspect_device_executable((app / executable).read_bytes())
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Bundle is not marked as an iPhoneOS device build.")
    if (app / "embedded.mobileprovision").exists():
        raise ValueError("Unexpected provisioning profile: this pipeline only produces unsigned apps.")
    destination.mkdir(parents=True, exist_ok=True)
    ipa = destination / "RCView-unsigned.ipa"
    with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_file():
                archive.write(path, (Path("Payload") / app.name / path.relative_to(app)).as_posix())
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{digest}  {ipa.name}\n", encoding="utf-8")
    (destination / "BUILD-INFO.json").write_text(json.dumps({
        "application": info.get("CFBundleDisplayName", "RC View"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "bundleIdentifier": info.get("CFBundleIdentifier"),
        "minimumOSVersion": info.get("MinimumOSVersion"),
        "sha256": digest,
        "signed": False,
        "installation": "Sign locally with Sideloadly and your own Apple account. Do not install this unsigned IPA directly.",
        "hardwareValidation": "Not established by a CI build; test on your iPad and UVC capture card.",
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Packaged {ipa} ({ipa.stat().st_size:,} bytes)")
    return ipa


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, default=Path("dist"))
    args = parser.parse_args()
    package(args.app, args.output)


if __name__ == "__main__":
    main()
