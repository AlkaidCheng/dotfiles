#!/usr/bin/env bash

if [[ -n "${BASH_VERSION:-}" ]]; then
    _SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    _SCRIPT_PATH="${(%):-%N}"
else
    _SCRIPT_PATH="$0"
fi
source "$(cd "$(dirname "$_SCRIPT_PATH")" && pwd)/../lib/guard.sh"
unset _SCRIPT_PATH
[[ ${_GUARD_DID_REEXEC:-0} -eq 1 ]] && { _rc=${_GUARD_RC:-0}; unset _GUARD_DID_REEXEC _GUARD_RC; return "$_rc"; }
unset _GUARD_DID_REEXEC _GUARD_RC

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
    echo "Hosts requiring a username (-u): lxplus, nersc, s3df"
    echo "Hosts with username handled internally: lrc"
    exit 1
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
    echo "Error: host '$HOST' requires a username (-u <username>)"
    exit 1
fi

# Locate the per-host script
HOST_SCRIPT="$SCRIPT_DIR/setup_${HOST}_key.sh"
if [[ ! -x "$HOST_SCRIPT" ]]; then
    echo "Error: script not found or not executable: $HOST_SCRIPT"
    exit 1
fi

# Delegate to the per-host script
if [[ "$NEEDS_USER" == true ]]; then
    "$HOST_SCRIPT" -u "$USERNAME"
else
    "$HOST_SCRIPT"
fi
