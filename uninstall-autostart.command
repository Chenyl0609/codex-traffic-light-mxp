#!/bin/zsh
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.codex.traffic-light-mxp.plist"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "Autostart removed"
