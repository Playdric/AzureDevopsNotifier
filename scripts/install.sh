#!/bin/zsh
# Copie l'app dans ~/Applications (requis pour Launch at login fiable).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d "build/ADO Notifier.app" ]] || scripts/bundle.sh
mkdir -p ~/Applications
rm -rf ~/Applications/"ADO Notifier.app"
cp -R "build/ADO Notifier.app" ~/Applications/
echo "Installed ~/Applications/ADO Notifier.app"
