#!/bin/bash
# Builds "build/Crumple.app" as a universal app (Apple silicon + Intel).
# Usage: ./build.sh [release|debug]
# Signs ad hoc by default. Set CRUMPLE_SIGN_ID to a "Developer ID Application: …" identity to sign
# for distribution (hardened runtime, secure timestamp); notarize.sh does that for you.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Each architecture gets its own build folder; otherwise they overwrite each other.
build_arch() {
    local localization="$(pwd)/.build/localization/$1"
    mkdir -p "$localization"
    local args=(-c "$CONFIG" --triple "$1-apple-macosx14.0" --scratch-path ".build/$1"
        -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$localization")
    swift build "${args[@]}" >&2 || return $?
    local bin
    bin=$(swift build "${args[@]}" --show-bin-path) || return $?
    echo "$bin/Crumple"
}
ARM=$(build_arch arm64)
INTEL=$(build_arch x86_64)

# Assemble the whole bundle in a staging folder and move it into place in one go, icon included.
# If macOS spots a half-built app without its icon, it caches the blank icon for that path.
STAGE="build/.staging/Crumple.app"
rm -rf build/.staging
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
lipo -create "$ARM" "$INTEL" -output "$STAGE/Contents/MacOS/Crumple"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
python3 Localization/generate.py .build/localization/arm64 "$STAGE/Contents/Resources"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$STAGE/Contents/MacOS/Crumple" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"
if [[ -n "${CRUMPLE_SIGN_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --entitlements Resources/Crumple.entitlements \
        --sign "$CRUMPLE_SIGN_ID" "$STAGE"
else
    codesign --force --sign - "$STAGE"
fi

APP="build/Crumple.app"
rm -rf "$APP"
mv "$STAGE" "$APP"
rm -rf build/.staging
touch "$APP"
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
echo "Built: $APP ($(lipo -archs "$APP/Contents/MacOS/Crumple"))"
