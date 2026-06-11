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

# ── Platform detection ───────────────────────────────────────
# Git Bash / MSYS2 / Cygwin report MINGW*/MSYS*/CYGWIN*; WSL
# reports Linux and needs no special handling.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *)                    IS_WINDOWS=false ;;
esac

# Convert a POSIX path to the platform-native form. Native Windows
# programs (e.g. MIT kinit.exe) cannot open MSYS-style /c/Users/...
# paths, and MSYS auto-converts command-line arguments only — not
# arbitrary environment variables like KRB5_CONFIG.
_native_path() {
    if [[ "$IS_WINDOWS" == true ]] && command -v cygpath &>/dev/null; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

if ! command -v kinit &>/dev/null; then
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            _bail "kinit not found. Install MIT Kerberos for Windows (https://web.mit.edu/kerberos/dist/) and open a new terminal so kinit.exe is on PATH"
            ;;
        Darwin)
            _bail "kinit not found. macOS ships kinit at /usr/bin/kinit — check that /usr/bin is on your PATH"
            ;;
        Linux)
            _bail "kinit not found. Install a Kerberos client: krb5-user (Debian/Ubuntu) or krb5-workstation (RHEL/Fedora)"
            ;;
        *)
            _bail "kinit not found. Install a Kerberos client for your platform"
            ;;
    esac
fi

DEFAULT_KRB5_CONFIG="$HOME/.config/krb5.conf"

if [[ -n "${KRB5_CONFIG:-}" ]]; then
    # Variable is set — verify the file exists
    if [[ ! -f "$KRB5_CONFIG" ]]; then
        _bail "KRB5_CONFIG is set to '$KRB5_CONFIG' but the file does not exist"
    fi
    # Re-export in native form (no-op outside Windows; idempotent if
    # the user already set a Windows-style path)
    KRB5_CONFIG="$(_native_path "$KRB5_CONFIG")"
    export KRB5_CONFIG
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
    KRB5_CONFIG="$(_native_path "$DEFAULT_KRB5_CONFIG")"
    export KRB5_CONFIG
fi

kinit "${USERNAME}@CERN.CH"