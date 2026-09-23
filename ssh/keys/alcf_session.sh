#!/usr/bin/env bash
set -euo pipefail

# ALCF systems authenticate with a one-time MobilePASS+ passcode; there is
# no key or certificate to fetch. The closest thing to a credential is a
# multiplexed master connection: open it once with a passcode, and every
# later ssh/scp/rsync to the same system rides on it until it has been
# idle for ControlPersist (set by ssh-remote-config).
#
# Shared by setup_aurora_key.sh and setup_polaris_key.sh.

usage() {
    echo "Usage: $0 <aurora|polaris>"
    exit 1
}

[[ $# -eq 1 ]] || usage
SYSTEM="$1"
case "$SYSTEM" in
    aurora|polaris) ;;
    *) echo "Error: unknown ALCF system '$SYSTEM'"; usage ;;
esac

# Effective value of one option, as ssh itself resolves it for the alias
_ssh_opt() { ssh -G "$SYSTEM" 2>/dev/null | awk -v k="$1" '$1 == k { print $2; exit }'; }

if [[ "$(_ssh_opt hostname)" != "$SYSTEM.alcf.anl.gov" ]]; then
    echo "Error: no SSH config for '$SYSTEM'." >&2
    echo "       Set one up: ssh-remote-config --$SYSTEM <alcf-username>" >&2
    exit 1
fi

if [[ "$(_ssh_opt controlmaster)" == false ]]; then
    echo "==> Connection sharing is not configured for $SYSTEM (not supported"
    echo "    by this platform's OpenSSH), so every connection asks for a fresh"
    echo "    MobilePASS+ passcode. Nothing to set up; just run: ssh $SYSTEM"
    exit 0
fi

if ssh -O check "$SYSTEM" &>/dev/null; then
    echo "==> A shared connection to $SYSTEM is already open; no passcode needed."
    exit 0
fi

CONTROL_DIR="$(dirname "$(_ssh_opt controlpath)")"
mkdir -p "$CONTROL_DIR" && chmod 700 "$CONTROL_DIR"

echo "==> Opening a shared connection to $SYSTEM.alcf.anl.gov as $(_ssh_opt user)"
echo "    At the password prompt, enter the passcode shown by the MobilePASS+"
echo "    app (open the app, select your token, enter your PIN). The PIN itself"
echo "    is never typed into ssh."
ssh "$SYSTEM" true

if ssh -O check "$SYSTEM" &>/dev/null; then
    PERSIST="$(_ssh_opt controlpersist)"
    echo
    echo "==> Connected. ssh, scp and rsync to $SYSTEM reuse this connection"
    if [[ "$PERSIST" =~ ^[0-9]+$ && "$PERSIST" -gt 0 ]]; then
        echo "    without a passcode until it has been idle for $(( PERSIST / 3600 ))h $(( PERSIST % 3600 / 60 ))m."
    else
        echo "    without a passcode while it stays open."
    fi
    echo "    Close it early with: ssh -O exit $SYSTEM"
else
    echo "Error: logged in, but no shared connection was left open." >&2
    echo "       Check that $CONTROL_DIR is writable." >&2
    exit 1
fi
