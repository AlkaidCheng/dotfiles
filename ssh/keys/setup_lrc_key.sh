#!/usr/bin/env bash
set -euo pipefail

LRC_SCRIPTS_REPO="https://github.com/lbnl-science-it/lrc-scripts.git"
LRC_SCRIPTS_DIR="$HOME/.ssh/lrc-scripts"
REQUEST_CERT="$LRC_SCRIPTS_DIR/request_cert.sh"

# Clone lrc-scripts if not already present
if [[ ! -x "$REQUEST_CERT" ]]; then
    echo "==> Cloning lrc-scripts to $LRC_SCRIPTS_DIR"
    git clone "$LRC_SCRIPTS_REPO" "$LRC_SCRIPTS_DIR"
    chmod +x "$REQUEST_CERT"
    echo "==> lrc-scripts installed at $LRC_SCRIPTS_DIR"
fi

"$REQUEST_CERT" -p lrc