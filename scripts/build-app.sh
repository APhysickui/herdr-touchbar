#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --disable-sandbox
APP="dist/Herdr Touch Bar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HerdrTouchBar "$APP/Contents/MacOS/HerdrTouchBar"
cp packaging/Info.plist "$APP/Contents/Info.plist"
if [[ -f packaging/HerdrTouchBar.icns ]]; then
  cp packaging/HerdrTouchBar.icns "$APP/Contents/Resources/HerdrTouchBar.icns"
fi
codesign --force --sign - "$APP"
print "Built: $PWD/$APP"
