#!/usr/bin/env python3
"""Package the supplied design as an opaque 1024px iOS app icon.

Regeneration requires Pillow (python -m pip install Pillow).
Xcode/Actions use the checked-in PNG and do not need Pillow.
The original composition is preserved without cropping or a rounded mask.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "design/assets/app-icon-source.png"
DESTINATION = ROOT / "RCView/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def main():
    with Image.open(SOURCE) as source:
        if source.width != source.height:
            raise SystemExit("The source must be square; cropping requires a design decision.")
        if source.mode != "RGB":
            raise SystemExit("The icon source must be opaque RGB.")
        icon = source.resize((1024, 1024), Image.Resampling.LANCZOS)
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        icon.save(DESTINATION, format="PNG", optimize=True)
    print("Packaged the supplied design as opaque 1024 x 1024 AppIcon.png")


if __name__ == "__main__":
    main()
