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

udid=$(Scripts/pick-simulator.sh)

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

xcodebuild build -project BuckFifty.xcodeproj -scheme BuckFifty -destination "id=$udid" \
  -derivedDataPath build/Screenshots CODE_SIGNING_ALLOWED=NO | tee build/screenshots-build.log
app=build/Screenshots/Build/Products/Debug-iphonesimulator/BuckFifty.app
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
