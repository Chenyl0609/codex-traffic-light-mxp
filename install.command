#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="CloudCodeLight"
APP_BUNDLE="$DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
HOOK_BIN="$DIR/.build/release/codex-light-hook-mxp"
CLI_BIN="$DIR/.build/release/codex-light-mxp"

echo "=== Cloud Code Light Installer ==="
echo ""

# Step 1: Build
echo "[1/4] Building..."
"$DIR/build.command"
echo ""

# Step 2: Create .app bundle and install
echo "[2/4] Installing app to $INSTALL_DIR..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$DIR/.build/release/CodexTrafficLightApp" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CloudCodeLight</string>
    <key>CFBundleDisplayName</key>
    <string>Cloud Code Light</string>
    <key>CFBundleIdentifier</key>
    <string>com.codex.traffic-light-mxp</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>CloudCodeLight</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
echo "  Installed: $INSTALL_DIR/$APP_NAME.app"
echo ""

# Step 3: Symlink CLI tools
echo "[3/4] Installing CLI tools..."
BIN_DIR="$HOME/.codex/bin"
mkdir -p "$BIN_DIR"
ln -sf "$CLI_BIN" "$BIN_DIR/codex-light-mxp"
ln -sf "$HOOK_BIN" "$BIN_DIR/codex-light-hook-mxp"
echo "  $BIN_DIR/codex-light-mxp"
echo "  $BIN_DIR/codex-light-hook-mxp"
echo ""

# Step 4: Merge hooks into ~/.claude/settings.json
echo "[4/4] Configuring Claude Code hooks..."

HOOK_CMD="$HOME/codex-traffic-light-mxp/.build/release/codex-light-hook-mxp"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cat > "$CLAUDE_SETTINGS" <<HOOKEOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD UserPromptSubmit",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD PreToolUse",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD Notification",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD Stop",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD SubagentStop",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
HOOKEOF
    echo "  Created $CLAUDE_SETTINGS with hooks"
else
    # Check if hooks already configured
    if grep -q "codex-light-hook-mxp" "$CLAUDE_SETTINGS" 2>/dev/null; then
        echo "  Hooks already configured, skipping"
    else
        # Use python3 to merge hooks into existing settings
        python3 -c "
import json, sys

with open('$CLAUDE_SETTINGS', 'r') as f:
    settings = json.load(f)

hook_cmd = '$HOOK_CMD'
hooks = {
    'UserPromptSubmit': [{'matcher': '', 'hooks': [{'type': 'command', 'command': hook_cmd + ' UserPromptSubmit', 'timeout': 5}]}],
    'PreToolUse': [{'matcher': '.*', 'hooks': [{'type': 'command', 'command': hook_cmd + ' PreToolUse', 'timeout': 5}]}],
    'Notification': [{'matcher': '', 'hooks': [{'type': 'command', 'command': hook_cmd + ' Notification', 'timeout': 5}]}],
    'Stop': [{'matcher': '', 'hooks': [{'type': 'command', 'command': hook_cmd + ' Stop', 'timeout': 5}]}],
    'SubagentStop': [{'matcher': '.*', 'hooks': [{'type': 'command', 'command': hook_cmd + ' SubagentStop', 'timeout': 5}]}]
}

if 'hooks' in settings:
    settings['hooks'].update(hooks)
else:
    settings['hooks'] = hooks

with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')
" && echo "  Merged hooks into $CLAUDE_SETTINGS" || echo "  Warning: failed to merge hooks, see Docs/hooks-claude-code.example.json"
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Launch from Launchpad or Spotlight: $APP_NAME"
echo "  2. In VS Code, when Claude Code triggers a hook for the first time,"
echo "     you'll be asked to trust the command. Select 'Always allow'."
echo ""

osascript -e "display dialog \"Installation complete!\n\nYou can now launch $APP_NAME from Launchpad or Spotlight.\n\nIn VS Code, the first hook trigger will ask you to trust the command — select 'Always allow'.\" buttons {\"OK\"} default button \"OK\" with title \"Cloud Code Light\""
