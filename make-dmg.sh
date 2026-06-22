#!/usr/bin/env bash
#
# make-dmg.sh — package Hopr.app into a drag-to-Applications .dmg installer.
#
# Produces the classic macOS installer experience: a disk image window showing
# Hopr.app on the left and a shortcut to /Applications on the right, so the user
# just drags the app across to install it.
#
# Usage:
#   ./make-dmg.sh                 # universal (arm64 + x86_64) release DMG
#   ./make-dmg.sh --native        # build only for this Mac's arch (faster)
#   ./make-dmg.sh --debug         # use the debug build
#   CODESIGN_ID="Developer ID Application: You (TEAMID)" ./make-dmg.sh
#
# Flags are passed straight through to package.sh, which builds the .app first.
#
set -euo pipefail

APP_NAME="Hopr"
VERSION="1.2.0"
VOL_NAME="$APP_NAME"
DMG_NAME="$APP_NAME-$VERSION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A universal (arm64 + x86_64) build needs full Xcode's xcbuild — the bare
# Command Line Tools can't cross-compile. If we're targeting universal and the
# active toolchain is only the CLT, point DEVELOPER_DIR at Xcode for the build.
WANT_UNIVERSAL=1
for arg in "$@"; do [[ "$arg" == "--native" ]] && WANT_UNIVERSAL=0; done
if [[ "$WANT_UNIVERSAL" == "1" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    if [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
        echo "==> Using Xcode toolchain for universal build: $DEVELOPER_DIR"
    else
        echo "warning: universal build needs full Xcode but none found;" >&2
        echo "         falling back may fail. Use --native for an arm64-only DMG." >&2
    fi
fi

# 1. Build the .app bundle (passes --native / --debug / CODESIGN_ID through).
echo "==> Building app bundle…"
"$ROOT/package.sh" "$@"

APP_PATH="$ROOT/dist/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found after build" >&2
    exit 1
fi

# 2. Stage the DMG contents: the app + a symlink to /Applications.
STAGE="$(mktemp -d)/$VOL_NAME"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Volume icon source. It is copied in AFTER the Finder layout step below —
# Finder deletes a pre-existing .VolumeIcon.icns when it rewrites .DS_Store.
ICNS="$ROOT/Resources/AppIcon.icns"

# Detach any stale volume from a previous run so we don't mount as "Hopr 1".
MOUNT_DIR="/Volumes/$VOL_NAME"
[[ -d "$MOUNT_DIR" ]] && hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true

# 3. Create a temporary read-write image so Finder can lay out the icons.
#    HFS+ is required: SetFile can't set the custom-icon flag on an APFS volume.
TMP_DMG="$(mktemp -u).dmg"
echo "==> Creating disk image…"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$TMP_DMG" >/dev/null

# 4. Mount it and arrange the window (app on the left, Applications on the right).
hdiutil attach "$TMP_DMG" -nobrowse -noautoopen >/dev/null

echo "==> Arranging installer window…"
osascript <<APPLESCRIPT || echo "   (window layout skipped — DMG is still valid)"
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 760, 480}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 120
        set position of item "$APP_NAME.app" of container window to {150, 190}
        set position of item "Applications" of container window to {410, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Now that Finder is done, drop in the volume icon and flag the volume as
# having a custom icon (doing this earlier gets clobbered by Finder).
if [[ -f "$ICNS" ]]; then
    cp "$ICNS" "$MOUNT_DIR/.VolumeIcon.icns"
    xcrun SetFile -a C "$MOUNT_DIR" 2>/dev/null || echo "   (volume icon flag skipped)"
fi

sync
# Detach with retries — Finder may briefly hold the volume after layout.
for _ in 1 2 3 4 5; do
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 && break
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 && break
done

# 5. Convert to a compressed, read-only image for distribution.
OUT="$ROOT/dist/$DMG_NAME.dmg"
rm -f "$OUT"
echo "==> Compressing…"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$TMP_DMG"

# 6. Give the .dmg file itself a custom Finder icon (separate from the volume
#    icon above). Embeds the icon into the file's resource fork.
if [[ -f "$ICNS" ]]; then
    echo "==> Setting .dmg file icon…"
    TMPICON="$(mktemp -d)/icon.png"
    if cp "$ROOT/assets/logo.png" "$TMPICON" 2>/dev/null \
        && sips -i "$TMPICON" >/dev/null 2>&1 \
        && xcrun DeRez -only icns "$TMPICON" > "${TMPICON}.rsrc" 2>/dev/null \
        && xcrun Rez -append "${TMPICON}.rsrc" -o "$OUT" 2>/dev/null; then
        xcrun SetFile -a C "$OUT" 2>/dev/null || true
    else
        echo "   (file icon skipped — DMG is still valid)"
    fi
fi

echo ""
echo "✅ Built $OUT"
echo "   Size: $(du -h "$OUT" | cut -f1)"
echo ""
echo "To install: open the .dmg and drag $APP_NAME into Applications."
