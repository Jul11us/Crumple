#!/bin/bash
# Builds, signs with your Developer ID, notarizes and staples "build/releases/Crumple <version>.dmg",
# so it opens on other Macs without a Gatekeeper warning.
#
# One-time setup (needs a paid Apple Developer account):
#   1. Install a "Developer ID Application" certificate in your login keychain.
#   2. Save notarization credentials (an app-specific password from appleid.apple.com):
#        xcrun notarytool store-credentials crumple --apple-id you@example.com --team-id ABCDE12345
#
# Then:
#   CRUMPLE_SIGN_ID="Developer ID Application: Your Name (ABCDE12345)" bash scripts/notarize.sh
#   (CRUMPLE_NOTARY_PROFILE defaults to "crumple")
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CRUMPLE_SIGN_ID:?Set CRUMPLE_SIGN_ID to your \"Developer ID Application: …\" identity (see the top of this file).}"
PROFILE="${CRUMPLE_NOTARY_PROFILE:-crumple}"

if ! security find-identity -v -p codesigning | grep -qF "$CRUMPLE_SIGN_ID"; then
    echo "找不到签名证书：$CRUMPLE_SIGN_ID" >&2
    echo "可用的证书：" >&2
    security find-identity -v -p codesigning >&2
    exit 1
fi

CRUMPLE_SIGN_ID="$CRUMPLE_SIGN_ID" bash scripts/build.sh release
codesign --verify --strict --deep "build/Crumple.app"

bash scripts/make-dmg.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/Crumple.app/Contents/Info.plist")
DMG="build/releases/Crumple $VERSION.dmg"
codesign --force --timestamp --sign "$CRUMPLE_SIGN_ID" "$DMG"

echo "上传公证，通常要几分钟…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "完成：$DMG"
