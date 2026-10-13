#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto "dist/Herdr Touch Bar.app" "$HOME/Applications/Herdr Touch Bar.app"
open "$HOME/Applications/Herdr Touch Bar.app"
print "Installed: $HOME/Applications/Herdr Touch Bar.app"
