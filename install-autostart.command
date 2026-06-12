#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.codex.traffic-light-mxp.plist"

"$DIR/build.command"
mkdir -p "$HOME/Library/LaunchAgents"

sed "s#__APP_PATH__#$DIR/.build/release/CodexTrafficLightApp#g" \
  "$DIR/com.codex.traffic-light-mxp.plist.template" > "$PLIST"

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"

echo "Autostart installed: $PLIST"
