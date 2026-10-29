#!/bin/zsh
# Génère Resources/AppIcon.icns depuis Resources/AppIcon/AppIcon.svg (rsvg-convert requis : brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."

SET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "${SET:h}"' EXIT
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size Resources/AppIcon/AppIcon.svg -o "$SET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/AppIcon/AppIcon.svg -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Built Resources/AppIcon.icns"
