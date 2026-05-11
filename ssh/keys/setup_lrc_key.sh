#!/usr/bin/env bash

if [[ -n "${BASH_VERSION:-}" ]]; then
    _SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    _SCRIPT_PATH="${(%):-%x}"
else
    _SCRIPT_PATH="$0"
fi
source "$(cd "$(dirname "$_SCRIPT_PATH")" && pwd)/../lib/guard.sh"
unset _SCRIPT_PATH
[[ ${_GUARD_DID_REEXEC:-0} -eq 1 ]] && { _rc=${_GUARD_RC:-0}; unset _GUARD_DID_REEXEC _GUARD_RC; return "$_rc"; }
unset _GUARD_DID_REEXEC _GUARD_RC

set -euo pipefail

LRC_SCRIPTS_REPO="https://github.com/lbnl-science-it/lrc-scripts.git"
LRC_SCRIPTS_DIR="$HOME/.ssh/lrc-scripts"
REQUEST_CERT="$LRC_SCRIPTS_DIR/request_cert.sh"

if [[ -d "$LRC_SCRIPTS_DIR" ]]; then
    # Directory exists — check it's a valid git repo before pulling
    if [[ -d "$LRC_SCRIPTS_DIR/.git" ]]; then
        echo "==> Updating lrc-scripts"
        git -C "$LRC_SCRIPTS_DIR" pull --ff-only
    else
        echo "Error: $LRC_SCRIPTS_DIR exists but is not a git repository"
        echo "       Remove it manually and re-run to clone fresh: rm -rf $LRC_SCRIPTS_DIR"
        exit 1
    fi
else
    echo "==> Cloning lrc-scripts to $LRC_SCRIPTS_DIR"
    git clone "$LRC_SCRIPTS_REPO" "$LRC_SCRIPTS_DIR"
fi

# Ensure the script is executable regardless of how it was cloned
if [[ ! -f "$REQUEST_CERT" ]]; then
    echo "Error: request_cert.sh not found in $LRC_SCRIPTS_DIR after clone/pull"
    echo "       The repository structure may have changed — check $LRC_SCRIPTS_REPO"
    exit 1
fi
chmod +x "$REQUEST_CERT"

"$REQUEST_CERT" -p lrc
