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

usage() {
    echo "Usage: $0 -u <username>"
    exit 1
}

# Parse arguments
USERNAME=""
while getopts "u:" opt; do
    case $opt in
        u) USERNAME="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Error: username is required"
    usage
fi

SSH_DIR="$HOME/.ssh/s3df"
KEY="$SSH_DIR/key"

echo "==> Setting up S3DF SSH key for user: $USERNAME"

# Setup the local directory for the key pair
echo "==> Creating $SSH_DIR"
mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"

# Remove old key if it exists
if [[ -f "$KEY" ]]; then
    echo "==> Removing old key"
    rm -f "$KEY" "$KEY.pub"
fi

# Generate a new key pair
echo "==> Generating ed25519 key pair"
ssh-keygen -t ed25519 -f "$KEY" -C "$USERNAME"

# Print the public key in standard OpenSSH format for upload to the portal
echo
echo "==> Setup complete. Upload the following public key to https://s3df-sshkeys.slac.stanford.edu:"
echo
cat "$KEY.pub"
