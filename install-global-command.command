#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.codex/bin"

"$DIR/build.command"
mkdir -p "$BIN_DIR"
ln -sf "$DIR/.build/release/codex-light-mxp" "$BIN_DIR/codex-light-mxp"
ln -sf "$DIR/.build/release/codex-light-hook-mxp" "$BIN_DIR/codex-light-hook-mxp"

echo "Installed:"
echo "  $BIN_DIR/codex-light-mxp"
echo "  $BIN_DIR/codex-light-hook-mxp"
