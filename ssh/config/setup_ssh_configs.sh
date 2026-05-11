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

# ============================================================
# Registry of supported hosts — add new hosts here
# Use an array so the script works whether run directly or sourced
# from zsh (which does not word-split plain strings in for-loops).
# ============================================================
SUPPORTED_HOSTS=(lxplus nersc lrc s3df)

# ============================================================
# Config templates — add a conf_<host>() function for each
# ============================================================
conf_lxplus() {
    local USER="$1"
    cat << CONF
Host lxplus lxplus[0-9]*
    HostName %h.cern.ch
    User $USER
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
    ForwardX11 yes
    ForwardX11Trusted yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
CONF
}

conf_nersc() {
    local USER="$1"
    cat << CONF
Host perlmutter saul dtn0[1-4]
    HostName %h.nersc.gov

Host nersc
    HostName perlmutter.nersc.gov

Host nersc perlmutter saul dtn0[1-4]
    User $USER
    IdentityFile ~/.ssh/nersc
    IdentitiesOnly yes
    ForwardAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
CONF
}

conf_lrc() {
    local USER="$1"
    cat << CONF
Host lrc
    HostName lrc-login.lbl.gov
    User $USER
    IdentityFile ~/.ssh/ssh_certs/lrc_cert
    ServerAliveInterval 60
    ServerAliveCountMax 3
CONF
}

conf_s3df() {
    local USER="$1"
    cat << CONF
Host s3df
    HostName s3dflogin-mfa.slac.stanford.edu
    User $USER
    IdentityFile ~/.ssh/s3df/key
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
CONF
}

# ============================================================
# Portable indirect variable expansion (bash and zsh).
# Reading: _getvar USER_lxplus  →  prints value of $USER_lxplus
# Writing: printf -v USER_lxplus '%s' "$val"  (unchanged — works in both)
# ============================================================
_getvar() { eval "printf '%s' \"\${$1}\""; }

# ============================================================
# Core logic
# ============================================================
CONFIGS_DIR="$HOME/.ssh/configs"
SSH_CONFIG="$HOME/.ssh/config"

usage() {
    echo "Usage: $0 [--<host> <username>]... [--all <username>]"
    echo
    echo "Supported hosts: ${SUPPORTED_HOSTS[*]}"
    echo "  --all <username>   Apply the same username to all hosts"
    # Use return when sourced so we don't kill the parent shell
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1
}

# Initialise per-host username variables
for host in "${SUPPORTED_HOSTS[@]}"; do
    printf -v "USER_${host}" '%s' ''
done

# Parse arguments
if [[ $# -eq 0 ]]; then usage; fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: --all requires a username"; usage; }
            for host in "${SUPPORTED_HOSTS[@]}"; do
                printf -v "USER_${host}" '%s' "$2"
            done
            shift 2
            ;;
        --*)
            host="${1#--}"
            # Validate against registry
            found=0
            for h in "${SUPPORTED_HOSTS[@]}"; do [[ "$h" == "$host" ]] && found=1; done
            [[ $found -eq 0 ]] && { echo "Error: unknown host '$host'"; usage; }
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: $1 requires a username"; usage; }
            printf -v "USER_${host}" '%s' "$2"
            shift 2
            ;;
        *) echo "Error: unknown option '$1'"; usage ;;
    esac
done

# Check at least one host was specified
any=0
for host in "${SUPPORTED_HOSTS[@]}"; do
    [[ -n "$(_getvar "USER_${host}")" ]] && any=1
done
[[ $any -eq 0 ]] && { echo "Error: at least one host must be specified"; usage; }

# Ensure ~/.ssh and ~/.ssh/config exist before any grep or read
mkdir -p "$CONFIGS_DIR"
mkdir -p "$(dirname "$SSH_CONFIG")"
if [[ ! -f "$SSH_CONFIG" ]]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
fi

install_conf() {
    local HOST="$1"
    local USER="$2"
    local CONF_FILE="$CONFIGS_DIR/${HOST}.conf"
    local INCLUDE_LINE="Include ~/.ssh/configs/${HOST}.conf"

    echo "==> Writing $CONF_FILE"
    "conf_${HOST}" "$USER" > "$CONF_FILE"

    if ! grep -qF "$INCLUDE_LINE" "$SSH_CONFIG"; then
        echo "==> Adding Include for ${HOST}.conf to $SSH_CONFIG"
        local EXISTING
        EXISTING=$(cat "$SSH_CONFIG")
        if [[ -z "$EXISTING" ]]; then
            printf '%s\n' "$INCLUDE_LINE" > "$SSH_CONFIG"
        else
            printf '%s\n\n%s\n' "$INCLUDE_LINE" "$EXISTING" > "$SSH_CONFIG"
        fi
    else
        echo "==> Include for ${HOST}.conf already present, skipping"
    fi
}

for host in "${SUPPORTED_HOSTS[@]}"; do
    username="$(_getvar "USER_${host}")"
    if [[ -n "$username" ]]; then
        install_conf "$host" "$username"
    fi
done

echo
echo "==> Done. Active includes in $SSH_CONFIG:"
grep "Include ~/.ssh/configs/" "$SSH_CONFIG"
