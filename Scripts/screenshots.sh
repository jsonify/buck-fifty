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

# Boot now and wait after the build: the simulator starts up while the app compiles.
xcrun simctl boot "$udid" 2>/dev/null || true

log=build/screenshots-build.log
echo "==> Building for the simulator (log: $log)"
if ! xcodebuild build -project BuckFifty.xcodeproj -scheme BuckFifty -destination "id=$udid" \
    -derivedDataPath build/Screenshots CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
  # Just the diagnostics, so they're the last thing in the CI log. -a: xcodebuild logs can look binary to grep.
  grep -aE "(error|warning): " "$log" | sort -u | head -60 >&2 || tail -40 "$log" >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi
app=build/Screenshots/Build/Products/Debug-iphonesimulator/BuckFifty.app
# The app icon compiled from the asset catalog (the home screen shows a blank one otherwise).
if ! ls "$app"/AppIcon*.png >/dev/null 2>&1; then
  echo "The app has no icon: check App/Assets.xcassets/AppIcon.appiconset." >&2
  exit 1
fi
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true

for appearance in light dark; do
  xcrun simctl ui "$udid" appearance "$appearance"
  for screen in home home-checklist home-levels stores list restock add trip map edit zone zones floorplan everything \
      you tour guide milestones milestones-levels; do
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$udid" "$bundle" -demo -demoScreen "$screen" >/dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot "$out/$screen-$appearance.png" >/dev/null
    echo "Saved $out/$screen-$appearance.png"
  done
done
