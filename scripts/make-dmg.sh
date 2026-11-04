#!/bin/bash
# Packs the app into a drag-to-install disk image: "build/releases/Crumple <version>.dmg".
# Builds the app first if needed. Laying out the window asks Finder for help, so the
# first run may show a macOS prompt to allow controlling Finder.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Crumple.app"
[ -d "$APP" ] || bash scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
VOLNAME="Crumple"
mkdir -p build/releases
DMG="build/releases/Crumple $VERSION.dmg"
STAGING="build/dmg-staging"
RW="build/dmg-rw.dmg"

# hdiutil still works but warns that it is deprecated on recent macOS; hide just those lines.
quiet() {
    local out
    if ! out=$("$@" 2>&1); then
        echo "$out" >&2
        return 1
    fi
    echo "$out" | grep -v "deprecated" || true
}

if [ -e "/Volumes/$VOLNAME" ]; then
    echo "请先推出已经挂载的「$VOLNAME」磁盘，再重新运行。" >&2
    exit 1
fi

# 1. What goes on the disk: the app, a link to /Applications, a background and a volume icon.
rm -rf "$STAGING" "$RW" "$DMG"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
"$APP/Contents/MacOS/Crumple" --render-dmg-background "$STAGING/.background"
tiffutil -cathidpicheck "$STAGING/.background/background.png" "$STAGING/.background/background@2x.png" \
    -out "$STAGING/.background/background.tiff" >/dev/null 2>&1
rm "$STAGING/.background/"*.png

# 2. A writable image we can arrange.
SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 20 ))
quiet hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null
ATTACH=$(quiet hdiutil attach -readwrite -noverify -noautoopen "$RW")
DEVICE=$(echo "$ATTACH" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT=$(echo "$ATTACH" | grep -o '/Volumes/.*' | head -1)

# 3. Window layout: icon positions, size and background (done by Finder, stored in .DS_Store).
LAYOUT=$(mktemp -t dmg-layout).applescript
cat > "$LAYOUT" <<'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 800, 548}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 100
            set text size of viewOptions to 13
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "Crumple.app" of container window to {150, 200}
            set position of item "Applications" of container window to {450, 200}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
APPLESCRIPT
osascript "$LAYOUT" "$(basename "$MOUNT")" &
OSA=$!
( sleep 120; kill "$OSA" 2>/dev/null ) &
WATCHDOG=$!
disown "$WATCHDOG"
if wait "$OSA"; then
    echo "窗口布局：已设置"
else
    echo "窗口布局：没能让访达排版（可能没允许控制访达），磁盘仍可正常安装，只是没有背景图。" >&2
fi
kill "$WATCHDOG" 2>/dev/null || true
rm -f "$LAYOUT"

# Volume icon. Done after the layout: opening the disk in Finder deletes .VolumeIcon.icns
# and clears the custom-icon flag (and hdiutil -srcfolder skips the file altogether).
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"

# 4. Seal it up as a compressed, read-only image.
rm -rf "$MOUNT/.fseventsd"
sync
for attempt in 1 2 3 4 5; do
    hdiutil detach "$DEVICE" >/dev/null 2>&1 && break
    sleep 2
done
quiet hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The copies used while laying out the disk got registered as apps; forget them again.
"$LSREGISTER" -u "$STAGING/Crumple.app" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$MOUNT/Crumple.app" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
rm -rf "$RW" "$STAGING"
"$LSREGISTER" -f /Applications/Crumple.app >/dev/null 2>&1 || true
echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"
