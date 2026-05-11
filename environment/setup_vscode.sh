#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSIONS_FILE="$SCRIPT_DIR/extensions.txt"

# Fail fast if extensions.txt is missing
if [ ! -f "$EXTENSIONS_FILE" ]; then
  echo "❌ extensions.txt not found at $EXTENSIONS_FILE"
  exit 1
fi

# Fail fast if code CLI is not available
if ! command -v code > /dev/null 2>&1; then
  echo "❌ 'code' CLI not found. Open VS Code and run: Shell Command: Install 'code' command in PATH"
  exit 1
fi

echo "Installing VS Code extensions..."

failed=0

while IFS= read -r line; do
  # Strip inline comments, leading/trailing whitespace
  ext=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Skip blank lines
  [ -z "$ext" ] && continue

  echo "Installing $ext..."
  if ! code --install-extension "$ext" --force; then
    echo "⚠️  Failed to install: $ext"
    failed=$((failed + 1))
  fi
done < "$EXTENSIONS_FILE"

if [ "$failed" -gt 0 ]; then
  echo "❌ Done with $failed failure(s). Check the output above."
  exit 1
else
  echo "✅ Done! Restart VS Code to activate all extensions."
fi