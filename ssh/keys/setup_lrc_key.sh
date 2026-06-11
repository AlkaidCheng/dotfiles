#!/usr/bin/env bash
set -euo pipefail

LRC_SCRIPTS_REPO="https://github.com/lbnl-science-it/lrc-scripts.git"
LRC_SCRIPTS_DIR="$HOME/.ssh/lrc-scripts"
REQUEST_CERT="$LRC_SCRIPTS_DIR/request_cert.sh"

usage() { echo "Usage: $0 -u <username>" >&2; exit 1; }

USERNAME=""
while getopts "u:h" opt; do
    case "$opt" in
        u) USERNAME="$OPTARG" ;;
        *) usage ;;
    esac
done
[[ -z "$USERNAME" ]] && { echo "Error: -u <username> is required" >&2; usage; }

if [[ -d "$LRC_SCRIPTS_DIR" ]]; then
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

if [[ ! -f "$REQUEST_CERT" ]]; then
    echo "Error: request_cert.sh not found in $LRC_SCRIPTS_DIR after clone/pull"
    echo "       The repository structure may have changed — check $LRC_SCRIPTS_REPO"
    exit 1
fi

# Always print the username so the user can see it whether auto-fill
# fires or not.
cat <<BANNER

============================================================
  LRC username: $USERNAME
  PIN and OTP will be prompted next (enter manually)
============================================================

BANNER

# Source-patch the upstream username prompt so it's pre-filled.
#
# Why patch instead of pipe: gen_cert() reads username, PIN, and OTP
# all from plain stdin via 'read -r'. Piping just the username would
# leave the next two reads with EOF — empty PIN/OTP → 401 from the
# server. Patching out the username read entirely lets PIN/OTP reads
# proceed normally from the terminal.
#
# Defensive: only patch if the exact upstream pattern is present;
# otherwise run the script unmodified and rely on the banner above.
# If LBNL ever changes the prompt format (e.g. printf instead of
# 'echo -n'), our grep misses and we degrade gracefully — the user
# just types the username from the banner.
PATTERN_ECHO='echo -n "Username: "'
PATTERN_READ='read -r user'

if grep -qF "$PATTERN_ECHO" "$REQUEST_CERT" && grep -qF "$PATTERN_READ" "$REQUEST_CERT"; then
    PATCHED=$(mktemp -t lrc_request_cert.XXXXXX.sh)
    trap 'rm -f "$PATCHED"' EXIT

    # The username travels through an env var rather than being
    # interpolated into the sed expression — sidesteps any escaping
    # concern even if the username happens to contain a sed
    # metacharacter (|, &, \, etc).
    sed \
        -e 's|echo -n "Username: "|echo "Username (auto-filled): ${LRC_USERNAME}"|' \
        -e 's|read -r user|user="${LRC_USERNAME}"|' \
        "$REQUEST_CERT" > "$PATCHED"

    LRC_USERNAME="$USERNAME" bash "$PATCHED" -p lrc
else
    echo "==> Note: upstream prompt format has changed; auto-fill skipped."
    echo "    Type the username shown above when prompted."
    bash "$REQUEST_CERT" -p lrc
fi
