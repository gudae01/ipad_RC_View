#!/usr/bin/env python3
"""Render the original RC View monitor icon. Standard library only; no downloaded art."""
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024


def rounded_distance(x, y, cx, cy, width, height, radius):
    qx = abs(x - cx) - (width / 2 - radius)
    qy = abs(y - cy) - (height / 2 - radius)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius


def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def main():
    background, ink = (248, 249, 250), (82, 109, 130)
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            monitor = abs(rounded_distance(x + .5, y + .5, 512, 464, 584, 384, 38)) - 14
            stand = rounded_distance(x + .5, y + .5, 512, 708, 28, 104, 14)
            base = rounded_distance(x + .5, y + .5, 512, 768, 236, 28, 14)
            # A small video-frame mark stays legible at home-screen icon sizes.
            mark = rounded_distance(x + .5, y + .5, 512, 464, 88, 88, 12)
            coverage = max(0.0, min(1.0, .5 - min(monitor, stand, base, mark)))
            rows.extend(round(b + (i - b) * coverage) for b, i in zip(background, ink))
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    catalog = ROOT / "RCView/Assets.xcassets"
    icon = catalog / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    (icon / "AppIcon.png").write_bytes(data)
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    (icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    print("Generated opaque 1024 x 1024 AppIcon.png")


if __name__ == "__main__":
    main()
