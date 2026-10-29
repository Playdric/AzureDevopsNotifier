#!/bin/zsh
# Build release universel (arm64 + x86_64) + assemble build/ADO Notifier.app + codesign.
# CODESIGN_IDENTITY : certificat stable (voir README), sinon signature ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/ADONotifier"
APP="build/ADO Notifier.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ADONotifier"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
