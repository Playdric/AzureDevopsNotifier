#!/bin/zsh
# Build release + assemble build/ADO Notifier.app + codesign.
# CODESIGN_IDENTITY : certificat stable (voir README), sinon signature ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ADONotifier"
APP="build/ADO Notifier.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ADONotifier"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --options runtime --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
