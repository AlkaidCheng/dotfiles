#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Registry of supported hosts — add new hosts here
# ============================================================
SUPPORTED_HOSTS="lxplus nersc lrc s3df"

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
# Core logic
# ============================================================
CONFIGS_DIR="$HOME/.ssh/configs"
SSH_CONFIG="$HOME/.ssh/config"

usage() {
    echo "Usage: $0 [--<host> <username>]... [--all <username>]"
    echo
    echo "Supported hosts: $SUPPORTED_HOSTS"
    echo "  --all <username>   Apply the same username to all hosts"
    exit 1
}

# Initialise per-host username variables
for host in $SUPPORTED_HOSTS; do
    eval "USER_${host}=''"
done

# Parse arguments
if [[ $# -eq 0 ]]; then usage; fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: --all requires a username"; usage; }
            for host in $SUPPORTED_HOSTS; do
                eval "USER_${host}='$2'"
            done
            shift 2
            ;;
        --*)
            host="${1#--}"
            case " $SUPPORTED_HOSTS " in
                *" $host "*) ;;
                *) echo "Error: unknown host '$host'"; usage ;;
            esac
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "Error: $1 requires a username"; usage; }
            eval "USER_${host}='$2'"
            shift 2
            ;;
        *) echo "Error: unknown option '$1'"; usage ;;
    esac
done

# Check at least one host was specified
any=0
for host in $SUPPORTED_HOSTS; do
    varname="USER_${host}"
    [[ -n "${!varname}" ]] && any=1
done
[[ $any -eq 0 ]] && { echo "Error: at least one host must be specified"; usage; }

mkdir -p "$CONFIGS_DIR"

install_conf() {
    local HOST="$1"
    local USER="$2"
    local CONF_FILE="$CONFIGS_DIR/${HOST}.conf"
    local INCLUDE_LINE="Include ~/.ssh/configs/${HOST}.conf"

    echo "==> Writing $CONF_FILE"
    "conf_${HOST}" "$USER" > "$CONF_FILE"

    if ! grep -qF "$INCLUDE_LINE" "$SSH_CONFIG"; then
        echo "==> Adding Include for ${HOST}.conf to $SSH_CONFIG"
        echo -en "${INCLUDE_LINE}\n\n$(< "$SSH_CONFIG")" > "$SSH_CONFIG"
    else
        echo "==> Include for ${HOST}.conf already present, skipping"
    fi
}

for host in $SUPPORTED_HOSTS; do
    varname="USER_${host}"
    username="${!varname}"
    if [[ -n "$username" ]]; then
        install_conf "$host" "$username"
    fi
done

echo
echo "==> Done. Active includes in $SSH_CONFIG:"
grep "Include ~/.ssh/configs/" "$SSH_CONFIG"
