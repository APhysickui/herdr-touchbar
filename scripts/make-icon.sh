#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
ICON_DIR=".build/HerdrTouchBar.iconset"
mkdir -p "$ICON_DIR"
.build/debug/HerdrTouchBar --render-icon .build/icon-source.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/icon-source.png --out "$ICON_DIR/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" .build/icon-source.png --out "$ICON_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_DIR" -o packaging/HerdrTouchBar.icns
