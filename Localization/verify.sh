#!/bin/bash
# Run the resource checks inside a real app bundle, where Locale.current follows its languages.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Crumple.app}"
CHECK=$(mktemp -d -t crumple-localization)
trap 'rm -rf "$CHECK"' EXIT
VERIFY="$CHECK/Verify.app"
mkdir -p "$VERIFY/Contents/MacOS"
cp "$APP/Contents/Info.plist" "$VERIFY/Contents/Info.plist"
ditto "$APP/Contents/Resources" "$VERIFY/Contents/Resources"
swiftc Localization/verify.swift -o "$VERIFY/Contents/MacOS/Crumple"
"$VERIFY/Contents/MacOS/Crumple" "$APP" en -AppleLanguages '(en)'
"$VERIFY/Contents/MacOS/Crumple" "$APP" zh-Hans -AppleLanguages '(zh-Hans)'
