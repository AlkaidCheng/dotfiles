#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Registry — add new hosts here
# Set NEEDS_USER_<host>=true if the script requires -u <username>
# ============================================================
SUPPORTED_HOSTS="lxplus nersc s3df lrc"

NEEDS_USER_lxplus=true
NEEDS_USER_nersc=true
NEEDS_USER_s3df=true
NEEDS_USER_lrc=false

# ============================================================
# Core logic
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 --host <host> [-u <username>]"
    echo
    echo "Supported hosts: $SUPPORTED_HOSTS"
    echo
    echo "If -u is omitted for a host that takes a username, it is auto-resolved"
    echo "from your SSH config via 'ssh -G <host>'. Run 'ssh-remote-config'"
    echo "first to install one. Pass -u explicitly to override."
    echo
    echo "Hosts that do not take a username: lrc (handled internally)"
    exit 1
}

# Resolve the User directive for a host alias by asking ssh itself.
# 'ssh -G' merges ~/.ssh/config and any files brought in via Include,
# applies Host pattern matches, and prints the effective config as
# lowercase key/value lines.
#
# Caveat: if no Host stanza matches, ssh -G still emits a `user`
# line — it falls back to the local username. Detect that case by
# probing a deliberately non-existent host alias and comparing; if
# the real host resolves to the same value, there's no host-specific
# config and we should fail with a helpful message rather than try
# kinit local-user@CERN.CH and confuse the user with a Kerberos
# "client not found" error.
_resolve_ssh_user() {
    local host="$1"
    command -v ssh &>/dev/null || return 1

    local resolved fallback
    resolved=$(ssh -G "$host" 2>/dev/null | awk '/^user /{print $2; exit}')
    fallback=$(ssh -G "_ssh_remote_auth_probe_$$" 2>/dev/null | awk '/^user /{print $2; exit}')

    if [[ -n "$resolved" && "$resolved" != "$fallback" ]]; then
        printf '%s' "$resolved"
        return 0
    fi
    return 1
}

HOST=""
USERNAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: --host requires a value"; usage; }
            HOST="$2"; shift 2 ;;
        -u|--username)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: -u requires a value"; usage; }
            USERNAME="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Error: unknown option '$1'"; usage ;;
    esac
done

if [[ -z "$HOST" ]]; then
    echo "Error: --host is required"
    usage
fi

# Validate host is in registry
case " $SUPPORTED_HOSTS " in
    *" $HOST "*) ;;
    *) echo "Error: unknown host '$HOST'. Supported: $SUPPORTED_HOSTS"; exit 1 ;;
esac

# Look up NEEDS_USER_<host>. Use ${var-UNDEFINED} (bash 3.2 compatible):
# unlike ${var:-UNDEFINED}, this only substitutes when the variable is
# truly unset, not when it is set-but-empty — catching missing registry
# entries even if someone sets NEEDS_USER_foo=''.
NEEDS_USER_VAR="NEEDS_USER_${HOST}"
NEEDS_USER="${!NEEDS_USER_VAR-UNDEFINED}"

if [[ "$NEEDS_USER" == "UNDEFINED" ]]; then
    echo "Error: host '$HOST' is listed in SUPPORTED_HOSTS but NEEDS_USER_${HOST} is not defined"
    echo "       Add 'NEEDS_USER_${HOST}=true' or 'NEEDS_USER_${HOST}=false' to the registry"
    exit 1
fi

if [[ "$NEEDS_USER" == true && -z "$USERNAME" ]]; then
    if USERNAME="$(_resolve_ssh_user "$HOST")"; then
        echo "==> Using username '$USERNAME' (from SSH config)"
    else
        echo "Error: no username configured for host '$HOST' in your SSH config." >&2
        echo "       Set one up: ssh-remote-config --$HOST <username>" >&2
        echo "       Or pass it: ssh-remote-auth --host $HOST -u <username>" >&2
        exit 1
    fi
fi

# Locate the per-host script. Test -f rather than -x and invoke via
# bash: the executable bit is unreliable on Windows filesystems (Git
# Bash / NTFS), and running through bash works identically everywhere.
HOST_SCRIPT="$SCRIPT_DIR/setup_${HOST}_key.sh"
if [[ ! -f "$HOST_SCRIPT" ]]; then
    echo "Error: script not found: $HOST_SCRIPT"
    exit 1
fi

# Delegate to the per-host script
if [[ "$NEEDS_USER" == true ]]; then
    bash "$HOST_SCRIPT" -u "$USERNAME"
else
    bash "$HOST_SCRIPT"
fi
