#!/usr/bin/env bash
#
# Builds Bank Tracker for iPhone and iPad, signs it with your Apple developer team, and installs
# it on a device paired with this Mac.
# Run with --help for options.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/BankTracker.xcodeproj"
SCHEME="BankTracker"
BUILD_DIR="$ROOT/build/ios"
DERIVED_DATA="$BUILD_DIR/DerivedData"

configuration="Release"
device=""
team="${DEVELOPMENT_TEAM:-}"

usage() {
    cat <<EOF
Usage: scripts/install-ios.sh [options]

Builds Bank Tracker for iPhone and iPad, signs it with your Apple developer team, and installs
it on a device paired with this Mac. Installing again keeps the app's data.

Before the first install:
  1. In Xcode, open Settings → Accounts and sign in with your Apple ID. A free account works.
  2. Connect the iPhone or iPad with a cable, unlock it, and tap Trust.
  3. On the device, turn on Settings → Privacy & Security → Developer Mode. It restarts.
The first time the app opens, the device asks you to trust your developer certificate, in
Settings → General → VPN & Device Management.

With a free account, the app stops opening after 7 days. Run this again to renew it.

Options:
  -d, --device NAME|ID      Device to install on (default: the only paired iPhone or iPad)
  -t, --team ID             Developer team ID (default: \$DEVELOPMENT_TEAM, or the only team
                            signed in to Xcode)
  -c, --configuration NAME  Release (default) or Debug
  -h, --help                Show this help
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device)
            [[ $# -ge 2 ]] || fail "$1 needs a device name or ID"
            device="$2"
            shift 2
            ;;
        -t|--team)
            [[ $# -ge 2 ]] || fail "$1 needs a team ID, like ABCDE12345"
            team="$2"
            shift 2
            ;;
        -c|--configuration)
            [[ $# -ge 2 ]] || fail "$1 needs a value: Release or Debug"
            configuration="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown option '$1' (see --help)" ;;
    esac
done

case "$(echo "$configuration" | tr '[:upper:]' '[:lower:]')" in
    release) configuration="Release" ;;
    debug) configuration="Debug" ;;
    *) fail "configuration must be Release or Debug, not '$configuration'" ;;
esac

command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode 26 or later."
mkdir -p "$BUILD_DIR"

# The team: given, or the only one signed in to Xcode.
if [[ -z "$team" ]]; then
    teams="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null |
        sed -n -E 's/.*teamID = "?([A-Z0-9]+)"?;.*/\1/p' | sort -u)"
    case "$(grep -c . <<<"$teams" || true)" in
        0) fail "no developer team found. Sign in to Xcode (Settings → Accounts), or pass --team." ;;
        1) team="$teams" ;;
        *) fail "Xcode has several teams ($(tr '\n' ' ' <<<"$teams")). Choose one with --team." ;;
    esac
fi

# The device: physical iPhones and iPads paired with this Mac, as "id<TAB>name<TAB>developer mode".
devices_json="$BUILD_DIR/devices.json"
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 ||
    fail "couldn't list devices (xcrun devicectl list devices)"
devices="$(python3 -I - "$devices_json" "$device" <<'PY'
import json, sys
wanted = sys.argv[2]
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hardware, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hardware.get("reality") != "physical" or hardware.get("platform") != "iOS":
        continue
    if d.get("connectionProperties", {}).get("pairingState") != "paired":
        continue
    udid, name = hardware.get("udid", ""), props.get("name", "")
    if wanted and wanted not in (udid, name, d.get("identifier")):
        continue
    print(f"{udid}\t{name}\t{props.get('developerModeStatus', '')}")
PY
)"
case "$(grep -c . <<<"$devices" || true)" in
    0)
        [[ -n "$device" ]] && fail "no paired iPhone or iPad called '$device'"
        fail "no paired iPhone or iPad. Connect one with a cable, unlock it, and tap Trust."
        ;;
    1) ;;
    *) fail "several devices are paired; choose one with --device: $(cut -f2 <<<"$devices" | paste -sd, - | sed 's/,/, /g')" ;;
esac
IFS=$'\t' read -r udid name developer_mode <<<"$devices"
if [[ "$developer_mode" != "enabled" ]]; then
    # The list can be out of date, for example right after the device restarts; ask the device.
    details_json="$BUILD_DIR/device.json"
    if xcrun devicectl device info details --device "$udid" --json-output "$details_json" >/dev/null 2>&1; then
        developer_mode="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["result"]["deviceProperties"].get("developerModeStatus", ""))' "$details_json" 2>/dev/null || true)"
    fi
fi
[[ "$developer_mode" == "enabled" ]] ||
    fail "Developer Mode is off on $name. Turn it on in Settings → Privacy & Security → Developer Mode; the device restarts. Then run this again."

step "Building $SCHEME ($configuration) for $name, signed with team $team"
build_log="$BUILD_DIR/build.log"
if ! xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -destination "id=$udid" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$team" >"$build_log" 2>&1; then
    grep -E "error:" "$build_log" | sort -u | head -n 20 >&2 || true
    if grep -q "login details .* were rejected\|Unable to log in" "$build_log"; then
        fail "Xcode's sign-in has expired. Sign in again in Xcode → Settings → Accounts, then run this again."
    fi
    fail "build failed (full log: ${build_log#"$ROOT"/})"
fi

app="$DERIVED_DATA/Build/Products/$configuration-iphoneos/BankTracker.app"
[[ -d "$app" ]] || fail "the build finished but $app is missing"
bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Info.plist")"

step "Installing Bank Tracker $version on $name"
xcrun devicectl device install app --device "$udid" "$app" >"$BUILD_DIR/install.log" 2>&1 ||
    { tail -n 20 "$BUILD_DIR/install.log" >&2; fail "install failed"; }

step "Opening it"
if ! xcrun devicectl device process launch --device "$udid" "$bundle_id" >"$BUILD_DIR/launch.log" 2>&1; then
    echo "    Installed, but it couldn't open yet. If this is the first install, trust your developer"
    echo "    certificate on $name in Settings → General → VPN & Device Management, then open it."
fi
step "Done. With a free Apple account it opens for 7 days; run this again to renew it."
