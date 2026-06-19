#!/usr/bin/env bash
#
# package.sh — build Hopr as a proper, code-signed Hopr.app bundle.
#
# SMAppService.mainApp ("Launch at Login") only works from a real, signed .app
# bundle. Running the bare SwiftPM executable fails with
# SMAppServiceErrorDomain Code=22 (Invalid argument). This script produces a
# bundle that satisfies those requirements.
#
# Usage:
#   ./package.sh                 # release, universal (arm64 + x86_64), ad-hoc
#                                # signed, output in ./dist
#   ./package.sh --debug         # use the debug build instead of release
#   ./package.sh --native        # build only for this Mac's arch (faster, for
#                                # local dev — won't run natively on the other arch)
#   CODESIGN_ID="Developer ID Application: You (TEAMID)" ./package.sh
#                                # sign with a real identity (needed for
#                                # distribution; ad-hoc is fine for local use)
#
set -euo pipefail

APP_NAME="Hopr"
BUNDLE_ID="com.hopr.app"
VERSION="1.2.0"
BUILD_NUMBER="2"
MIN_MACOS="13.0"

CONFIG="release"
UNIVERSAL=1
for arg in "$@"; do
    case "$arg" in
        --debug)  CONFIG="debug" ;;
        --native) UNIVERSAL=0 ;;
        *) echo "warning: ignoring unknown option '$arg'" >&2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGN_ID="${CODESIGN_ID:--}"   # default to ad-hoc signing

# Build universal (arm64 + x86_64) by default so the .app runs natively on both
# Apple Silicon and Intel Macs. --native drops the cross-arch slice for faster
# local dev builds.
BUILD_FLAGS=(-c "$CONFIG")
if [[ "$UNIVERSAL" == "1" ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
    echo "==> Building $APP_NAME ($CONFIG, universal: arm64 + x86_64)…"
else
    echo "==> Building $APP_NAME ($CONFIG, native arch only)…"
fi
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: built executable not found at $EXECUTABLE" >&2
    exit 1
fi

APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Assembling bundle at ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# Copy resources flat — the app looks them up via Bundle.main.resourcePath.
if [[ -d "$ROOT/Resources" ]]; then
    cp -R "$ROOT/Resources/." "$RES_DIR/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Code signing (identity: $SIGN_ID)…"
codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

echo ""
echo "✅ Built $APP_DIR"
echo "   Architectures: $(lipo -archs "$MACOS_DIR/$APP_NAME")"
echo ""
echo "Next steps to enable Launch at Login:"
echo "  • Run it:        open \"$APP_DIR\""
echo "  • Or install it: cp -R \"$APP_DIR\" /Applications/ && open \"/Applications/$APP_NAME.app\""
echo ""
echo "Note: ad-hoc signing works for running on this Mac. For distribution to"
echo "other machines, re-run with CODESIGN_ID set to a Developer ID identity."
