#!/bin/bash
# Copies build/Crumple.app into /Applications (replacing an older copy) so it shows up
# in Finder, Launchpad and Spotlight with its icon. Builds it first if needed.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Crumple.app"
[ -d "$APP" ] || bash ./build.sh
if pgrep -xq Crumple; then
    echo "Crumple 正在运行，先退出它再安装。" >&2
    exit 1
fi
rm -rf /Applications/Crumple.app
ditto "$APP" /Applications/Crumple.app
touch /Applications/Crumple.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Crumple.app >/dev/null 2>&1 || true
echo "Installed: /Applications/Crumple.app"
