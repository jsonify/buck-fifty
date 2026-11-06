#!/bin/bash
# Prints the UDID of the iPhone simulator to use: one already booted, or else the newest iOS runtime's iPhone, a Pro
# (not a Max) if there is one. Its name and iOS version go to stderr.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    for d in devices:
        if not d.get("isAvailable") or not d["name"].startswith("iPhone"):
            continue
        booted = d.get("state") == "Booted"
        pro = "Pro" in d["name"] and "Max" not in d["name"]
        score = (booted, (int(m[1]), int(m[2])), pro, d["name"])
        if best is None or score > best[0]:
            best = (score, d["udid"], d["name"])
if best is None:
    sys.exit("No iPhone simulator available: add one in Xcode (Window > Devices and Simulators).")
version = best[0][1]
print(best[1])
print(f"Simulator: {best[2]}, iOS {version[0]}.{version[1]}", file=sys.stderr)
'
