#!/usr/bin/env python3
"""Select the newest available iPad simulator already installed on the runner."""
import json
from pathlib import Path
import re
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
candidates = []
for runtime, devices in payload.get("devices", {}).items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(v) for v in re.findall(r"\d+", runtime.rsplit(".iOS-", 1)[-1]))
    if not version or version[0] < 17:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPad"):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    raise SystemExit("No available iPad simulator (iPadOS 17+) found. Select an Xcode runner with an iOS runtime installed.")
print(sorted(candidates, reverse=True)[0][2])
