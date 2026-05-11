#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_FILE="$SCRIPT_DIR/vscode_extensions.txt"

if [[ ! -f "$EXTENSIONS_FILE" ]]; then
  echo "❌ vscode_extensions.txt not found at $EXTENSIONS_FILE"
  exit 1
fi

# Read extensions, stripping comments and blank lines
mapfile -t extensions < <(grep -v '^\s*#' "$EXTENSIONS_FILE" | grep -v '^\s*$')

echo "Installing ${#extensions[@]} VS Code extensions..."

for ext in "${extensions[@]}"; do
  echo "Installing $ext..."
  code --install-extension "$ext" --force
done

echo "✅ Done! Restart VS Code to activate all extensions."