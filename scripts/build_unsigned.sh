#!/bin/bash
# Run on a macOS machine with Xcode (GitHub Actions uses this script).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 scripts/generate_project.py
python3 scripts/validate_project.py
xcodebuild -version
xcodebuild \
  -project RCView.xcodeproj \
  -scheme RCView \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/RCView.app --output dist
python3 scripts/validate_project.py --ipa dist/RCView-unsigned.ipa
