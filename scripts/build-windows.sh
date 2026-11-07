#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
DOTNET_BIN="${CRUMPLE_DOTNET:-dotnet}"
if ! command -v "$DOTNET_BIN" >/dev/null 2>&1; then
  if [[ -x "$ROOT/build/windows-tools/dotnet/dotnet" ]]; then
    DOTNET_BIN="$ROOT/build/windows-tools/dotnet/dotnet"
  else
    echo "Install .NET 10 SDK, or set CRUMPLE_DOTNET to its executable." >&2
    exit 1
  fi
fi
RID="${1:-win-x64}"
case "$RID" in win-x64|win-arm64) ;; *) echo "Use win-x64 or win-arm64." >&2; exit 1;; esac
OUT="$ROOT/build/windows/$RID"
RELEASES="$ROOT/build/releases/windows"
mkdir -p "$OUT" "$RELEASES"
# English strings come from the Mac version's translations; this fails if any Chinese text has none.
python3 scripts/windows-strings.py
"$DOTNET_BIN" run --project Windows/Crumple.Core.Tests -c Release
"$DOTNET_BIN" publish Windows/Crumple.Desktop/Crumple.Desktop.csproj -c Release -r "$RID" -o "$OUT"
NAME="Crumple-1.2.0-Windows-${RID#win-}"
cp "$OUT/Crumple.exe" "$RELEASES/$NAME.exe"
python3 scripts/package-windows.py "$RID"
MAKENSIS_BIN="${CRUMPLE_MAKENSIS:-makensis}"
if ! command -v "$MAKENSIS_BIN" >/dev/null 2>&1 && [[ -x "$ROOT/build/windows-tools/nsis-3.13/makensis" ]]; then
  MAKENSIS_BIN="$ROOT/build/windows-tools/nsis-3.13/makensis"
fi
if [[ "$RID" == "win-x64" ]] && command -v "$MAKENSIS_BIN" >/dev/null 2>&1; then
  if [[ "$MAKENSIS_BIN" == "$ROOT/build/windows-tools/nsis-3.13/makensis" ]]; then
    export NSISDIR="$ROOT/build/windows-tools/nsis-3.13"
  fi
  # makensis converts text through iconv and aborts under the plain C locale.
  LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$MAKENSIS_BIN" -V2 "-DAPP_EXE=$OUT/Crumple.exe" "-DOUTPUT_FILE=$RELEASES/$NAME-Setup.exe" \
    "-DNOTICES=$RELEASES/THIRD-PARTY-NOTICES.txt" Windows/installer/Crumple.nsi
else
  echo "Standalone exe built. NSIS is needed only for the x64 Setup exe."
fi
python3 scripts/verify-windows-package.py "$RELEASES"
