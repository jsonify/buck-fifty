#!/bin/bash
# Builds Buck Fifty from the terminal, without opening Xcode.
#
#   Scripts/dist.sh              build for the iOS Simulator into dist/BuckFifty.app
#   Scripts/dist.sh --run        build, then open it in the Simulator (the one booted, or the newest iPhone)
#   Scripts/dist.sh --demo       with --run: open on the sample Costco list instead of your own data
#   Scripts/dist.sh --install    build for your iPhone (plugged in, or paired over Wi-Fi), install it and open it
#
# Flags combine. DEVICE=<name or id> picks the iPhone when more than one is connected: any unique part of its name
# will do, in any case, with straight or curly apostrophes (DEVICE=kitties). The full xcodebuild log is kept at
# build/dist.log.
set -euo pipefail
cd "$(dirname "$0")/.."

run=0; demo=0; install=0
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    --demo) demo=1 ;;
    --install) install=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
bundle=com.jsonify.buckfifty

echo "==> Generating BuckFifty.xcodeproj"
xcodegen generate --quiet

# The build number is the commit count, so a build on the phone says which one it is.
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if ! git diff --quiet HEAD -- 2>/dev/null; then commit="$commit-dirty"; fi

if [ "$install" = 1 ]; then
  # A connected iPhone, from devicectl (Xcode 15+).
  devices_json=$(mktemp)
  xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 || true
  device=$(DEVICE="${DEVICE:-}" python3 - "$devices_json" <<'PY'
import json, os, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
def fold(s):
    # Case and curly quotes don't matter: an iPhone called "Big Ol’ Kitties" matches DEVICE="big ol' kitties".
    return s.replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"').lower().strip()
want = fold(os.environ.get("DEVICE", ""))
phones = []
for d in devices:
    hw, props, conn = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or conn.get("tunnelState") == "unavailable":
        continue
    ids = [fold(d.get("identifier", "")), fold(hw.get("udid", "")), fold(props.get("name", ""))]
    phones.append((d["identifier"], props.get("name", "iPhone"), ids))
if not phones:
    sys.exit("No iPhone found. Plug it in (or pair it in Xcode > Window > Devices and Simulators), unlock it, and try again.")
names = ", ".join(n for _, n, _ in phones)
if want:
    # The name or id exactly, else any phone whose name has it in it ("kitties").
    found = [p for p in phones if want in p[2]] or [p for p in phones if want in p[2][2]]
    if not found:
        sys.exit(f"No iPhone matches DEVICE={os.environ['DEVICE']}. Connected: {names}")
    if len(found) > 1:
        sys.exit(f"DEVICE={os.environ['DEVICE']} matches more than one iPhone: " + ", ".join(n for _, n, _ in found))
else:
    found = phones
if len(found) > 1:
    sys.exit("More than one iPhone: pick one with DEVICE=<name> (part of the name will do): " + names)
print(found[0][0])
print(f"iPhone: {found[0][1]}", file=sys.stderr)
PY
)
  rm -f "$devices_json"
  configuration=Release
  destination=(-destination 'generic/platform=iOS')
  products=Release-iphoneos
else
  udid=$(Scripts/pick-simulator.sh)
  configuration=Debug
  destination=(-destination "id=$udid")
  products=Debug-iphonesimulator
fi

mkdir -p build
log=build/dist.log
# Two builds sharing build/DerivedData fail with "database is locked"; say so up front instead.
if pgrep -f "xcodebuild.*-derivedDataPath build/DerivedData" >/dev/null 2>&1; then
  echo "Another Buck Fifty build is still running (an earlier make in another tab?). Wait for it, or: pkill xcodebuild" >&2
  exit 1
fi
echo "==> Building $configuration (log: $log)"
if ! xcodebuild -project BuckFifty.xcodeproj -scheme BuckFifty -configuration "$configuration" "${destination[@]}" \
    CURRENT_PROJECT_VERSION="$build_number" -allowProvisioningUpdates -derivedDataPath build/DerivedData \
    build >"$log" 2>&1; then
  # -a: xcodebuild logs can hold bytes that make grep call the file binary and print nothing useful.
  grep -aE "error:|BUILD FAILED" "$log" | tail -20 >&2 || tail -20 "$log" >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi

app=dist/BuckFifty.app
rm -rf dist && mkdir dist
ditto "build/DerivedData/Build/Products/$products/BuckFifty.app" "$app"
echo "==> Built $(pwd)/$app ($products, build $build_number, $commit)"

if [ "$install" = 1 ]; then
  echo "==> Installing on the iPhone"
  xcrun devicectl device install app --device "$device" "$app" >/dev/null
  echo "==> Opening Buck Fifty on the iPhone"
  xcrun devicectl device process launch --terminate-existing --device "$device" "$bundle" >/dev/null
  exit 0
fi

if [ "$run" = 1 ]; then
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator --args -CurrentDeviceUDID "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$app"
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  launch_args=()
  [ "$demo" = 1 ] && launch_args=(-demo)
  echo "==> Opening Buck Fifty in the Simulator${launch_args[*]:+ (${launch_args[*]})}"
  xcrun simctl launch "$udid" "$bundle" ${launch_args[@]+"${launch_args[@]}"} >/dev/null
fi
