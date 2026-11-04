#!/bin/bash
# Copies build/Crumple.app into /Applications (replacing an older copy) so it shows up
# in Finder, Launchpad and Spotlight with its icon. Builds it first if needed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Crumple.app"
[ -d "$APP" ] || bash scripts/build.sh
if pgrep -xq Crumple; then
    echo "Crumple 正在运行，先退出它再安装。" >&2
    exit 1
fi
rm -rf /Applications/Crumple.app
ditto "$APP" /Applications/Crumple.app
touch /Applications/Crumple.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Only the installed copy should be registered; build and packaging copies would compete with it.
for copy in "$PWD/build/Crumple.app" "$PWD/build/dmg-staging/Crumple.app" "$PWD/build/.staging/Crumple.app"; do
    "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
done
"$LSREGISTER" -f -R -trusted /Applications/Crumple.app >/dev/null 2>&1 || true
mdimport /Applications/Crumple.app >/dev/null 2>&1 || true
echo "Installed: /Applications/Crumple.app"
