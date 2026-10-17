#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED=${NIMBAR_DERIVED_DATA:-/private/tmp/NimBarBuild}
APP=${NIMBAR_PACKAGE_APP:-/private/tmp/NimBar.app}
OUT=${NIMBAR_PACKAGE_OUT:-"$ROOT/build/packages"}
# Keep the original imported identity: never select another certificate by name.
SIGNING_IDENTITY=${NIMBAR_SIGNING_IDENTITY:-6A1A131688AC29BD01914E366951696097276710}
SIGNING_TEAM=${NIMBAR_SIGNING_TEAM:-L4R3ATNCT8}
SIGNING_KEYCHAIN=${NIMBAR_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}
WORK=$(mktemp -d /private/tmp/NimBarPackaging.XXXXXX)
MOUNT="$WORK/mount"
PUBLISH_STAGE=
cleanup() {
    if [ -d "$MOUNT" ]; then hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; fi
    if [ -n "$PUBLISH_STAGE" ]; then rm -rf "$PUBLISH_STAGE"; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

case "${1:-}" in
    ''|--check-signing) ;;
    *) echo "Usage: Scripts/package.sh [--check-signing]" >&2; exit 2 ;;
esac
case "$APP" in
    /*.app) ;;
    *) echo "Errore: NIMBAR_PACKAGE_APP deve essere un percorso assoluto a un bundle .app." >&2; exit 2 ;;
esac
if ! IDENTITIES=$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>&1) \
    || ! printf '%s\n' "$IDENTITIES" | grep -F " $SIGNING_IDENTITY " >/dev/null; then
    echo "Errore: l’identità NimBar prevista non è accessibile nel Portachiavi selezionato." >&2
    echo "Il sandbox può restituire zero identità anche con un certificato valido: riesegui con accesso al Portachiavi prima di importare o sostituire certificati." >&2
    echo "Nessun pacchetto creato o sostituito; la firma ad hoc non è consentita." >&2
    exit 2
fi
# A listed certificate alone does not prove that its private key is usable.
printf 'int main(void) { return 0; }\n' > "$WORK/signing-probe.c"
xcrun clang "$WORK/signing-probe.c" -o "$WORK/signing-probe"
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$WORK/signing-probe"
codesign --verify --strict "$WORK/signing-probe"
PROBE_INFO=$(codesign -dvvv "$WORK/signing-probe" 2>&1)
if ! printf '%s\n' "$PROBE_INFO" | grep -Fx "TeamIdentifier=$SIGNING_TEAM" >/dev/null; then
    echo "Errore: Team ID del certificato diverso dall’identità NimBar prevista." >&2
    exit 2
fi
if [ "${1:-}" = --check-signing ]; then
    echo "Firma NimBar verificata: certificato originale, chiave privata utilizzabile e Team ID corretto."
    exit 0
fi

cd "$ROOT"
xcodebuild -project NimBar.xcodeproj -scheme NimBar -configuration Release -sdk macosx \
    -derivedDataPath "$DERIVED" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM="$SIGNING_TEAM" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
SOURCE_APP="$DERIVED/Build/Products/Release/NimBar.app"
SIGNED_APP="$WORK/NimBar.app"
ditto "$SOURCE_APP" "$SIGNED_APP"
xattr -cr "$SIGNED_APP"
codesign --force --deep --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$SIGNED_APP"
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"
SIGNATURE_INFO=$(codesign -dvvv --requirements - "$SIGNED_APP" 2>&1)
if printf '%s\n' "$SIGNATURE_INFO" | grep -q 'Signature=adhoc' \
    || ! printf '%s\n' "$SIGNATURE_INFO" | grep -Fx "TeamIdentifier=$SIGNING_TEAM" >/dev/null; then
    echo "Errore: firma ad hoc o Team ID inatteso; pacchetti non generati." >&2
    exit 2
fi
codesign -d --extract-certificates="$WORK/certificate-" "$SIGNED_APP"
LEAF_SHA1=$(shasum "$WORK/certificate-0" | awk '{print toupper($1)}')
if [ "$LEAF_SHA1" != "$SIGNING_IDENTITY" ]; then
    echo "Errore: il certificato incorporato non corrisponde all’identità originale prevista." >&2
    exit 2
fi

mkdir -p "$OUT" "$MOUNT" "$WORK/content/.background" "$WORK/swift-cache" "$WORK/clang-cache"
PUBLISH_STAGE=$(mktemp -d "$OUT/.packaging.XXXXXX")
DMG="$PUBLISH_STAGE/NimBar.dmg"
ZIP="$PUBLISH_STAGE/NimBar.zip"
ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP" "$ZIP"
ditto "$SIGNED_APP" "$WORK/content/NimBar.app"
ln -s /Applications "$WORK/content/Applications"
SWIFT_MODULECACHE_PATH="$WORK/swift-cache" CLANG_MODULE_CACHE_PATH="$WORK/clang-cache" \
    xcrun swift "$ROOT/Scripts/dmg-background.swift" "$WORK/content/.background/installer.png"
hdiutil create -volname NimBar -srcfolder "$WORK/content" -ov -format UDRW "$WORK/installer.dmg"
hdiutil attach -readwrite -nobrowse -mountpoint "$MOUNT" "$WORK/installer.dmg"
python3 "$ROOT/Scripts/configure-dmg.py" "$MOUNT"
sync
hdiutil detach "$MOUNT"
hdiutil convert "$WORK/installer.dmg" -format UDZO -o "$DMG"
codesign --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"

# Verify what users install, rather than only the app used as packaging input.
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
codesign --verify --deep --strict "$MOUNT/NimBar.app"
cmp "$SIGNED_APP/Contents/MacOS/NimBar" "$MOUNT/NimBar.app/Contents/MacOS/NimBar"
cmp "$SIGNED_APP/Contents/Info.plist" "$MOUNT/NimBar.app/Contents/Info.plist"
test "$(readlink "$MOUNT/Applications")" = /Applications
test -f "$MOUNT/.DS_Store"
hdiutil detach "$MOUNT"
mkdir "$WORK/zip-verification"
ditto -x -k "$ZIP" "$WORK/zip-verification"
codesign --verify --deep --strict "$WORK/zip-verification/NimBar.app"
cmp "$SIGNED_APP/Contents/MacOS/NimBar" "$WORK/zip-verification/NimBar.app/Contents/MacOS/NimBar"
cmp "$SIGNED_APP/Contents/Info.plist" "$WORK/zip-verification/NimBar.app/Contents/Info.plist"
(cd "$PUBLISH_STAGE" && shasum -a 256 NimBar.zip NimBar.dmg > SHA256SUMS.txt)
# Replace outputs only after every signature and package check has passed.
rm -rf "$APP"
ditto "$SIGNED_APP" "$APP"
mv -f "$DMG" "$OUT/NimBar.dmg"
mv -f "$ZIP" "$OUT/NimBar.zip"
mv -f "$PUBLISH_STAGE/SHA256SUMS.txt" "$OUT/SHA256SUMS.txt"
# Only discard older NimBar archives after the replacement packages have
# passed signature, content and integrity verification.
for obsolete in "$OUT"/NimBar-*.dmg "$OUT"/NimBar-*.zip; do
    [ -f "$obsolete" ] || continue
    rm -f -- "$obsolete" "$obsolete.sha256"
done
echo "Pacchetti NimBar firmati e verificati: $OUT"
