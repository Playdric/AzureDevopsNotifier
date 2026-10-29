#!/bin/zsh
# Build l'app (signature ad-hoc) + build/ADO-Notifier-<version>.dmg (glisser vers Applications).
# --publish : crée la release GitHub v<version> avec le dmg (gh requis).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP="build/ADO Notifier.app"
DMG="build/ADO-Notifier-$VERSION.dmg"

# Ad-hoc : un certificat local n'a aucune valeur chez les autres utilisateurs.
CODESIGN_IDENTITY=- scripts/bundle.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "ADO Notifier" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Built $DMG"

if [[ "${1:-}" == "--publish" ]]; then
  gh release create "v$VERSION" "$DMG" --title "v$VERSION" --generate-notes
fi
