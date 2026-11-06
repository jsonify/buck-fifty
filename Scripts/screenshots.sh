#!/usr/bin/env bash
# Builds the app for the newest iPhone simulator, runs it on the sample list (-demo) and saves a screenshot of each
# screen in light and dark to the folder given (default: screenshots/). Needs Xcode and a generated project
# (xcodegen generate). CI runs it and uploads the folder.
#
#   Scripts/screenshots.sh [out-dir]
set -euo pipefail
out="${1:-screenshots}"
mkdir -p "$out" build
bundle=com.jsonify.buckfifty

# The newest iOS runtime's iPhone, a Pro (not a Max) if there is one.
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    for d in devices:
        if not d.get("isAvailable") or not d["name"].startswith("iPhone"):
            continue
        pro = "Pro" in d["name"] and "Max" not in d["name"]
        score = ((int(m[1]), int(m[2])), pro, d["name"])
        if best is None or score > best[0]:
            best = (score, d["udid"], d["name"])
if best is None:
    sys.exit("No iPhone simulator available")
print(best[1])
print(f"Simulator: {best[2]}, iOS {best[0][0][0]}.{best[0][0][1]}", file=sys.stderr)
')

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

xcodebuild build -project BuckFifty.xcodeproj -scheme BuckFifty -destination "id=$udid" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO | tee build/screenshots-build.log
app=build/Build/Products/Debug-iphonesimulator/BuckFifty.app
xcrun simctl install "$udid" "$app"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true

for appearance in light dark; do
  xcrun simctl ui "$udid" appearance "$appearance"
  for screen in stores list add trip edit zones; do
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$udid" "$bundle" -demo -demoScreen "$screen" >/dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot "$out/$screen-$appearance.png" >/dev/null
    echo "Saved $out/$screen-$appearance.png"
  done
done
