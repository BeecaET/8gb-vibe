#!/bin/bash
# Release build: universal (Apple silicon + Intel), Developer ID signature, hardened runtime, notarization, DMG.
#
# Usage:
#   NOTARY_PROFILE=<notarytool profile> ./scripts/release.sh
#
# Create the notarytool profile once (stores the app-specific password in the Keychain):
#   xcrun notarytool store-credentials <profile> --apple-id <email> --team-id 59SQ2V25T2
#
# Without NOTARY_PROFILE: still signs and builds the DMG but skips notarization (Gatekeeper warns on other Macs).
# Output: build/release/8GB-Vibe-<version>.dmg and a .sha256 file
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

OUT="build/release"
APP="$OUT/$DISPLAY_NAME.app"
DMG="$OUT/${DISPLAY_NAME// /-}-$VERSION.dmg"

if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: uncommitted changes. Release builds should come from a clean commit."
fi

SIGN="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$SIGN" ]; then
    echo "Error: no Developer ID Application certificate found in the Keychain." >&2
    exit 1
fi
echo "Signing with: $SIGN"

echo "1/6 Building universal (arm64 + x86_64)..."
swift build -c release -j 2 --arch arm64 --arch x86_64 --product "$NAME"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$NAME"
lipo -info "$BIN"

echo "2/6 Packaging and signing the app..."
rm -rf "$OUT"; mkdir -p "$OUT"
make_bundle "$BIN" "$APP"
codesign --force --options runtime --timestamp --sign "$SIGN" "$APP"
codesign --verify --strict --verbose=2 "$APP"

notarize() {
    local file="$1"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "3/6 Notarizing the app..."
    ZIP="$OUT/$NAME-app.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
else
    echo "3/6 Skipping notarization (NOTARY_PROFILE not set)."
fi

echo "4/6 Creating the DMG..."
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "5/6 Notarizing the DMG..."
    notarize "$DMG"
    xcrun stapler staple "$DMG"
else
    echo "5/6 Skipping DMG notarization."
fi

echo "6/6 Verifying..."
spctl -a -vv --type execute "$APP" 2>&1 || true
spctl -a -vv --type open --context context:primary-signature "$DMG" 2>&1 || true
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Done: $DMG ($VERSION, build $BUILD_NUMBER)"
