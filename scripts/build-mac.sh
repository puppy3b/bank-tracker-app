#!/usr/bin/env bash
#
# Builds the Bank Tracker macOS app into build/BankTracker.app.
# Run with --help for options.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/BankTracker.xcodeproj"
SCHEME="BankTracker"
APP_NAME="BankTracker.app"
PROCESS_NAME="BankTracker"
BUILD_DIR="$ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"

configuration="Release"
clean=false
run_tests=false
open_app=false
install_app=false
make_zip=false
verbose=false

usage() {
    cat <<EOF
Usage: scripts/build-mac.sh [options]

Builds the Bank Tracker macOS app into build/$APP_NAME.

Options:
  -c, --configuration NAME  Release (default) or Debug
      --clean               Delete previous build output first
      --test                Run the BankTrackerCore unit tests before building
      --zip                 Also package the app as build/BankTracker-VERSION-macOS.zip,
                            with a SHA-256 checksum file next to it
      --install             Copy the app to /Applications (or ~/Applications if
                            /Applications isn't writable; set INSTALL_DIR to choose)
      --open                Launch the app when done
  -v, --verbose             Show the full xcodebuild output
  -h, --help                Show this help

Examples:
  scripts/build-mac.sh                    # Release build
  scripts/build-mac.sh --test --install   # test, build, then install
  scripts/build-mac.sh -c Debug --open    # Debug build, then launch it
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
        -c|--configuration)
            [[ $# -ge 2 ]] || fail "$1 needs a value: Release or Debug"
            configuration="$2"
            shift 2
            ;;
        --clean) clean=true; shift ;;
        --test) run_tests=true; shift ;;
        --zip) make_zip=true; shift ;;
        --install) install_app=true; shift ;;
        --open) open_app=true; shift ;;
        -v|--verbose) verbose=true; shift ;;
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

if $clean; then
    step "Removing ${BUILD_DIR#"$ROOT"/}/"
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

if $run_tests; then
    step "Running BankTrackerCore tests"
    test_log="$BUILD_DIR/test.log"
    if swift test --package-path "$ROOT/BankTrackerCore" --scratch-path "$BUILD_DIR/core" >"$test_log" 2>&1; then
        grep -E "Test run with" "$test_log" | tail -n 1 | sed 's/^/    /' || true
    else
        grep -E "✘|error:" "$test_log" | head -n 40 >&2 || true
        fail "tests failed (full log: ${test_log#"$ROOT"/})"
    fi
fi

step "Building $SCHEME ($configuration)"
build_log="$BUILD_DIR/build.log"
build_command=(
    xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$configuration"
    -destination "generic/platform=macOS"
    -derivedDataPath "$DERIVED_DATA"
    build
)
if $verbose; then
    "${build_command[@]}" 2>&1 | tee "$build_log" || fail "build failed (full log: ${build_log#"$ROOT"/})"
elif ! "${build_command[@]}" >"$build_log" 2>&1; then
    grep -E "error:" "$build_log" | sort -u | head -n 40 >&2 || true
    fail "build failed (full log: ${build_log#"$ROOT"/})"
fi

built_app="$DERIVED_DATA/Build/Products/$configuration/$APP_NAME"
[[ -d "$built_app" ]] || fail "the build finished but $built_app is missing"

app="$BUILD_DIR/$APP_NAME"
rm -rf "$app"
ditto "$built_app" "$app"
codesign --verify --deep --strict "$app" || fail "code signature check failed for $app"

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null || echo "unknown")"
step "Built ${app#"$ROOT"/} (version $version, $configuration)"

if $make_zip; then
    zip_name="BankTracker-$version-macOS.zip"
    rm -f "$BUILD_DIR/$zip_name" "$BUILD_DIR/$zip_name.sha256"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$BUILD_DIR/$zip_name"
    (cd "$BUILD_DIR" && shasum -a 256 "$zip_name" >"$zip_name.sha256")
    step "Packaged ${BUILD_DIR#"$ROOT"/}/$zip_name"
fi

if $install_app; then
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
        fail "Bank Tracker is running. Quit it, then run the script again with --install."
    fi
    install_dir="${INSTALL_DIR:-}"
    if [[ -z "$install_dir" ]]; then
        if [[ -w /Applications ]]; then
            install_dir="/Applications"
        else
            install_dir="$HOME/Applications"
        fi
    fi
    mkdir -p "$install_dir"
    rm -rf "${install_dir:?}/$APP_NAME"
    ditto "$app" "$install_dir/$APP_NAME"
    app="$install_dir/$APP_NAME"
    step "Installed $app"
fi

if $open_app; then
    step "Opening $app"
    open "$app"
elif ! $install_app; then
    echo "    Launch it with: open ${app#"$ROOT"/}"
fi
