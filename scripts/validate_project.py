#!/usr/bin/env python3
"""Portable structure checks. These do not compile Swift or validate UVC hardware."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile

from generate_project import ROOT, generate
from package_ipa import inspect_device_executable


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_project() -> None:
    sources = sorted((ROOT / "RCView").rglob("*.swift"))
    require(bool(sources), "No Swift app sources found.")
    require((ROOT / "RCView/RCViewApp.swift").is_file(), "Missing app entry point.")
    require(bool(list((ROOT / "Tests").glob("*.swift"))), "Missing XCTest source files.")
    for path, expected in generate().items():
        require(path.exists() and path.read_text(encoding="utf-8") == expected, "Project is stale; run scripts/generate_project.py.")
    project = (ROOT / "RCView.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    identifiers = re.findall(r"^\t\t([A-F0-9]{24}) = \{", project, re.M)
    require(len(identifiers) == len(set(identifiers)), "Duplicate PBX object identifiers.")
    all_references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    require(all_references <= set(identifiers), "PBX reference points to an absent object.")
    scheme = ET.parse(ROOT / "RCView.xcodeproj/xcshareddata/xcschemes/RCView.xcscheme")
    for reference in scheme.findall(".//BuildableReference"):
        require(reference.attrib["BlueprintIdentifier"] in identifiers, "Scheme references an absent target.")
    info = plistlib.loads((ROOT / "RCView/Info.plist").read_bytes())
    require(bool(info.get("NSCameraUsageDescription")), "Missing camera permission explanation.")
    permission_keys = {key for key in info if key.startswith("NS") and key.endswith("UsageDescription")}
    require(permission_keys == {"NSCameraUsageDescription"}, "Unexpected additional permission request.")
    require("UIBackgroundModes" not in info, "Unexpected background capture capability.")
    require(info.get("UIRequiresFullScreen") is False, "Window resizing must remain available.")
    require(len(info.get("UISupportedInterfaceOrientations~ipad", [])) == 4, "Missing iPad rotation support.")
    require('TARGETED_DEVICE_FAMILY = "2";' in project, "App must target iPad only.")
    require('IPHONEOS_DEPLOYMENT_TARGET = "17.0";' in project, "Unexpected minimum iPadOS target.")
    require("DEVELOPMENT_TEAM =" not in project, "Do not embed an Apple developer team.")
    require("CODE_SIGN_ENTITLEMENTS" not in project, "No additional entitlements are expected.")
    for manifest_path in (ROOT / "RCView/Assets.xcassets").rglob("Contents.json"):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in manifest.get("images", []):
            if "filename" in entry:
                require((manifest_path.parent / entry["filename"]).is_file(), f"Missing asset: {entry['filename']}")
    icon = (ROOT / "RCView/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
    require(icon[:8] == b"\x89PNG\r\n\x1a\n", "App icon is not PNG.")
    width, height, depth, color = struct.unpack_from(">IIBB", icon, 16)
    require((width, height, depth, color) == (1024, 1024, 8, 2), "Icon must be 1024-square opaque RGB.")
    workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")
    require("workflow_dispatch:" in workflow and "\n  schedule:" not in workflow, "Expected manual workflow.")
    require("runs-on: macos-latest" in workflow, "Expected standard macOS runner.")
    require("retention-days: 1" in workflow, "Expected short artifact retention.")
    require("${{ secrets." not in workflow, "Apple secrets must not be used in this workflow.")
    for path in (ROOT / "scripts").glob("*.sh"):
        require(b"\r\n" not in path.read_bytes(), f"Shell script has CRLF: {path.name}")
    print(f"PASS: {len(sources)} Swift source references, project/scheme, plist, icon and workflow structure.")
    print("NOT CHECKED HERE: Swift compilation, signing, iPad installation, UVC or RC 2 behavior.")


def validate_ipa(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate entries in IPA.")
        require(all(not p.startswith("/") and ".." not in Path(p).parts for p in names), "Unsafe path in IPA.")
        info_name = "Payload/RCView.app/Info.plist"
        require(info_name in names, "Missing Payload/RCView.app/Info.plist.")
        require(all(p.startswith("Payload/RCView.app/") for p in names), "Unexpected bundle root.")
        require(not any(p.endswith("embedded.mobileprovision") for p in names), "IPA unexpectedly contains a personal profile.")
        info = plistlib.loads(archive.read(info_name))
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "IPA contains a simulator build.")
        require(info.get("UIDeviceFamily") == [2], "IPA is not iPad-only.")
        executable = "Payload/RCView.app/" + info["CFBundleExecutable"]
        inspect_device_executable(archive.read(executable))
        mode = archive.getinfo(executable).external_attr >> 16
        require(bool(mode & 0o111), "IPA lost executable permissions.")
        require(bool(info.get("NSCameraUsageDescription")), "IPA lacks camera permission copy.")
    print(f"PASS: unsigned device IPA structure, arm64/iOS binary, executable permissions: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path)
    args = parser.parse_args()
    try:
        validate_project()
        if args.ipa:
            validate_ipa(args.ipa)
        return 0
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
