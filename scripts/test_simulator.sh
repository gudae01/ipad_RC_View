#!/bin/bash
# A simulator verifies compilation and pure logic, never real USB/UVC behavior.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
SIMULATOR_ID="$(python3 scripts/select_simulator.py build/simulators.json)"
xcodebuild \
  -project RCView.xcodeproj \
  -scheme RCView \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -destination-timeout 120 \
  -derivedDataPath build/simulator \
  -resultBundlePath "build/TestResults-$(date +%s).xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test
