#!/usr/bin/env bash
#
# Retakes the iPhone screenshots in docs/screenshots from the app's sample data.
#
# It builds a Debug copy for the iOS Simulator, runs it on a simulated iPhone 16 Pro with
# --demo --tour, and screenshots each page as the tour steps through. Everything happens in
# the simulator, in the background: no window opens and the Mac stays free to use. The sample
# data lives in memory, so your own data never appears.
#
# Needs the iOS Simulator runtime (Xcode → Settings → Components, or
# `xcodebuild -downloadPlatform iOS`). The first run creates a simulator called
# "Bank Tracker iPhone 16 Pro".
#
# Usage: scripts/make-ios-screenshots.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/ios-screenshots"
OUTPUT="$ROOT/docs/screenshots"
DEVICE_NAME="Bank Tracker iPhone 16 Pro"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
BUNDLE_ID="com.zibin.BankTracker"
# Screenshots are 3x; half size is plenty for the README and keeps the files small.
SCALE_WIDTH=603

# Tour stop → file in docs/screenshots. Stops not listed here aren't kept.
doc_name() {
    case "$1" in
        dashboard) echo "iphone-today.png" ;;
        account-inProgress) echo "iphone-account.png" ;;
        offers) echo "iphone-offers.png" ;;
        stats) echo "iphone-statistics.png" ;;
        *) echo "" ;;
    esac
}

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

runtime="$(xcrun simctl list runtimes --json | python3 -I -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
print(runtimes[-1]["identifier"] if runtimes else "")
')"
[[ -n "$runtime" ]] || fail "no iOS Simulator runtime. Install one with: xcodebuild -downloadPlatform iOS"

step "Preparing the simulator"
udid="$(xcrun simctl list devices --json | python3 -I -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d.get("isAvailable"):
            print(d["udid"]); raise SystemExit
' "$DEVICE_NAME")"
if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$runtime")"
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4
xcrun simctl ui "$udid" appearance light

step "Building a Debug copy for the simulator"
mkdir -p "$WORK"
if ! xcodebuild build \
    -project "$ROOT/BankTracker.xcodeproj" \
    -scheme BankTracker \
    -configuration Debug \
    -destination "id=$udid" \
    -derivedDataPath "$WORK/DerivedData" >"$WORK/build.log" 2>&1; then
    grep -E "error:" "$WORK/build.log" | sort -u | head -n 20 >&2 || true
    fail "build failed (full log: ${WORK#"$ROOT"/}/build.log)"
fi
xcrun simctl install "$udid" "$WORK/DerivedData/Build/Products/Debug-iphonesimulator/BankTracker.app"

step "Running the tour"
captures="$WORK/captures"
rm -rf "$captures" && mkdir -p "$captures"
finished=false
while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
        "TOUR done") finished=true; break ;;
        "TOUR "*)
            name="${line#TOUR }"
            xcrun simctl io "$udid" screenshot --type=png "$captures/$name.png" >/dev/null 2>&1 &&
                echo "    captured $name"
            ;;
    esac
done < <(xcrun simctl launch --console-pty --terminate-running-process "$udid" "$BUNDLE_ID" --demo --tour 2>/dev/null)
$finished || fail "the tour stopped early (screenshots so far: ${captures#"$ROOT"/})"
xcrun simctl status_bar "$udid" clear

step "Saving to ${OUTPUT#"$ROOT"/}"
mkdir -p "$OUTPUT"
for capture in "$captures"/*.png; do
    name="$(doc_name "$(basename "$capture" .png)")"
    [[ -n "$name" ]] || continue
    sips --resampleWidth "$SCALE_WIDTH" "$capture" --out "$OUTPUT/$name" >/dev/null
    echo "    ${OUTPUT#"$ROOT"/}/$name"
done
