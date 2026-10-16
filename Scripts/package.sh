#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED=${MENU_LITE_DERIVED_DATA:-/private/tmp/NimBarBuild}
APP=${MENU_LITE_PACKAGE_APP:-/private/tmp/NimBar.app}
OUT=${MENU_LITE_PACKAGE_OUT:-"$ROOT/build/packages"}
SIGNING_IDENTITY=${MENU_LITE_SIGNING_IDENTITY:-Apple Development}
SIGNING_TEAM=${MENU_LITE_SIGNING_TEAM:-L4R3ATNCT8}

cd "$ROOT"
xcodebuild -project NimBar.xcodeproj -scheme NimBar -configuration Release -sdk macosx \
    -derivedDataPath "$DERIVED" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$SIGNING_TEAM" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
SOURCE_APP="$DERIVED/Build/Products/Release/NimBar.app"
DMG="$OUT/NimBar.dmg"
ZIP="$OUT/NimBar.zip"
ditto "$SOURCE_APP" "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
SIGNATURE_INFO=$(codesign -dvvv --requirements - "$APP" 2>&1)
if printf '%s\n' "$SIGNATURE_INFO" | grep -q 'Signature=adhoc' \
    || ! printf '%s\n' "$SIGNATURE_INFO" | grep -F "TeamIdentifier=$SIGNING_TEAM" >/dev/null; then
    echo "Errore: firma ad hoc o Team ID inatteso; pacchetti non generati." >&2
    printf '%s\n' "$SIGNATURE_INFO" >&2
    exit 2
fi
# Verify every nested code object as well as the outer app before packaging.
codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
DMG_STAGE=$(mktemp -d /private/tmp/NimBarDiskImage.XXXXXX)
DMG_MOUNT=$(mktemp -d /private/tmp/NimBarDiskMount.XXXXXX)
DMG_RW="$DMG_STAGE/installer.dmg"
cleanup() {
    hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
    rm -rf "$DMG_STAGE" "$DMG_MOUNT"
}
trap cleanup EXIT
mkdir -p "$DMG_STAGE/content/.background"
ditto "$APP" "$DMG_STAGE/content/NimBar.app"
ln -s /Applications "$DMG_STAGE/content/Applications"
xcrun swift "$ROOT/Scripts/dmg-background.swift" "$DMG_STAGE/content/.background/installer.png"
hdiutil create -volname NimBar -srcfolder "$DMG_STAGE/content" -ov -format UDRW "$DMG_RW"
hdiutil attach -readwrite -nobrowse -mountpoint "$DMG_MOUNT" "$DMG_RW"
python3 "$ROOT/Scripts/configure-dmg.py" "$DMG_MOUNT"
sync
hdiutil detach "$DMG_MOUNT"
rm -f "$DMG"
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG"
(cd "$OUT" && shasum -a 256 NimBar.zip NimBar.dmg > SHA256SUMS.txt)
