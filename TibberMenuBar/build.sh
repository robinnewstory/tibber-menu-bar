#!/bin/zsh
# Generates the Xcode project, builds Tibber Menu Bar.app and installs it into /Applications.
# Usage: TibberMenuBar/build.sh [--no-install]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
XCODEGEN="$(find "$ROOT/.tools" /Users/robin/Projects/ring-widget/.tools -type f -name xcodegen -perm -u+x 2>/dev/null | head -1 || true)"
INSTALL=1
for a in "$@"; do case "$a" in --no-install) INSTALL=0 ;; esac; done
if [[ -z "$XCODEGEN" ]]; then
  echo "xcodegen not found — download xcodegen.zip from https://github.com/yonaskolb/XcodeGen/releases and unzip into $ROOT/.tools/" >&2
  exit 1
fi
cd "$HERE"
"$XCODEGEN" generate --spec project.yml --quiet
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig | tr -d '[:space:]')"
if [[ -z "$TEAM" ]]; then
  echo "No DEVELOPMENT_TEAM in Config/Local.xcconfig (copy Local.xcconfig.example)." >&2
  exit 1
fi
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
LOG="$ROOT/.tools/xcodebuild.log"
mkdir -p "$ROOT/.tools"
xcodebuild -project TibberMenuBar.xcodeproj -scheme TibberMenuBar -configuration Release \
  -derivedDataPath "$ROOT/.tools/DerivedData" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" -allowProvisioningUpdates build > "$LOG" 2>&1 || true
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$LOG" || true
if ! grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "Build failed; nothing installed. Full log: $LOG" >&2
  exit 1
fi
APP="$ROOT/.tools/DerivedData/Build/Products/Release/Tibber Menu Bar.app"
if [[ $INSTALL -eq 1 ]]; then
  if pgrep -xq "Tibber Menu Bar"; then osascript -e 'quit app "Tibber Menu Bar"' || true; sleep 1; fi
  rm -rf "/Applications/Tibber Menu Bar.app"
  ditto "$APP" "/Applications/Tibber Menu Bar.app"
  echo "Installed /Applications/Tibber Menu Bar.app (build $BUILD_NUMBER)"
  open "/Applications/Tibber Menu Bar.app"
else
  echo "Built: $APP"
fi
