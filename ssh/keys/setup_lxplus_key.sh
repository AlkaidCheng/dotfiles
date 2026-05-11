#!/usr/bin/env bash

_bail() {
    echo "Error: $1" >&2
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1
}

usage() {
    echo "Usage: $0 -u <username>"
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1
}

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

DEFAULT_KRB5_CONFIG="$HOME/.config/krb5.conf"

if [[ -n "${KRB5_CONFIG:-}" ]]; then
    # Variable is set — verify the file exists
    if [[ ! -f "$KRB5_CONFIG" ]]; then
        _bail "KRB5_CONFIG is set to '$KRB5_CONFIG' but the file does not exist"
    fi
else
    # Variable is not set — use default path, creating config if needed
    if [[ ! -f "$DEFAULT_KRB5_CONFIG" ]]; then
        echo "==> Creating default Kerberos config at $DEFAULT_KRB5_CONFIG"
        mkdir -p "$(dirname "$DEFAULT_KRB5_CONFIG")"
        cat > "$DEFAULT_KRB5_CONFIG" << 'CONF'
[libdefaults]
    default_realm = CERN.CH
    ticket_lifetime = 25h
    renew_lifetime = 120h
    forwardable = true
    proxiable = true

[realms]
    CERN.CH = {
        kdc = cerndc.cern.ch
        master_kdc = cerndc.cern.ch
        default_domain = cern.ch
        kpasswd_server = afskrb5m.cern.ch
        admin_server = afskrb5m.cern.ch
    }

[domain_realm]
    .cern.ch = CERN.CH
    cern.ch = CERN.CH
CONF
    fi
    export KRB5_CONFIG="$DEFAULT_KRB5_CONFIG"
fi

kinit "${USERNAME}@CERN.CH"