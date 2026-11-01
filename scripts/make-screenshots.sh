#!/usr/bin/env bash
#
# Retakes the README screenshots in docs/screenshots from the app's sample data.
#
# It builds a Debug copy of the app (in its own folder, so build/BankTracker.app isn't
# touched), launches it with --demo --tour, and captures the window as the tour steps through
# the screens. The sample data lives in memory, so your own data and settings never appear.
#
# Terminal (or whichever app runs this) needs Screen Recording permission, in System Settings →
# Privacy & Security. Leave the Mac alone while it runs (about a minute): the window has to stay
# in front, and the tour stops without saving anything if it loses focus or is clicked.
#
# Usage: scripts/make-screenshots.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/screenshots"
OUTPUT="$ROOT/docs/screenshots"
MAX_WIDTH=1600

# Tour screen → file in docs/screenshots. Screens not listed here aren't kept.
doc_name() {
    case "$1" in
        dashboard) echo "today.png" ;;
        dashboard-dark) echo "today-dark.png" ;;
        accounts) echo "accounts.png" ;;
        account-inProgress) echo "account.png" ;;
        offer-detail) echo "offer-eligibility.png" ;;
        taxes) echo "taxes.png" ;;
        stats) echo "statistics.png" ;;
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

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

step "Building a Debug copy"
mkdir -p "$WORK"
if ! xcodebuild build \
    -project "$ROOT/BankTracker.xcodeproj" \
    -scheme BankTracker \
    -configuration Debug \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$WORK/DerivedData" >"$WORK/build.log" 2>&1; then
    grep -E "error:" "$WORK/build.log" | sort -u | head -n 20 >&2 || true
    fail "build failed (full log: ${WORK#"$ROOT"/}/build.log)"
fi
app="$WORK/DerivedData/Build/Products/Debug/BankTracker.app"

step "Running the tour"
# The app's output goes to a temporary folder: `open --stdout` can't write into protected
# folders such as Desktop or Documents, where the repository may live.
log="$(mktemp -d)/tour.log"
captures="$WORK/captures"
rm -rf "$captures" && mkdir -p "$captures"
: >"$log"
# `open` puts the window in front, which launching the binary directly doesn't always do.
open -n -a "$app" --stdout "$log" --stderr /dev/null --args --demo --tour -ApplePersistenceIgnoreState YES

seen=0
finished=false
deadline=$((SECONDS + 120))
while ((SECONDS < deadline)); do
    total=$(wc -l <"$log" | tr -d ' ')
    while ((seen < total)); do
        seen=$((seen + 1))
        read -r tag name window <<<"$(sed -n "${seen}p" "$log")"
        [[ "$tag" == "TOUR" ]] || continue
        case "$name" in
            done) finished=true ;;
            failed*) fail "the tour stopped. $(sed -n "${seen}p" "$log" | sed 's/^TOUR failed: //')" ;;
            *)
                screencapture -o -x -l "$window" "$captures/$name.png"
                echo "    captured $name"
                ;;
        esac
    done
    $finished && break
    sleep 0.2
done
$finished || fail "the tour didn't finish within two minutes (log: $log)"

step "Saving to ${OUTPUT#"$ROOT"/}"
mkdir -p "$OUTPUT"
for capture in "$captures"/*.png; do
    name="$(doc_name "$(basename "$capture" .png)")"
    [[ -n "$name" ]] || continue
    cp "$capture" "$OUTPUT/$name"
    width=$(sips -g pixelWidth "$OUTPUT/$name" | awk '/pixelWidth/ { print $2 }')
    if ((width > MAX_WIDTH)); then
        sips --resampleWidth "$MAX_WIDTH" "$OUTPUT/$name" >/dev/null
    fi
    echo "    ${OUTPUT#"$ROOT"/}/$name"
done
