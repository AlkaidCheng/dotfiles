#!/usr/bin/env bash

# Prints credential status for each HPC facility.
# Does not acquire or refresh anything — read-only.

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

_header() { echo -e "\n${BOLD}── $1 ──${RESET}"; }
_ok()     { echo -e "  ${GREEN}✔${RESET}  $1"; }
_warn()   { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
_err()    { echo -e "  ${RED}✘${RESET}  $1"; }

# Convert an epoch timestamp to "YYYY-MM-DD HH:MM:SS"
_fmt_date() {
    date -r "$1" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || date -d "@$1" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || echo "(unknown)"
}

# Format remaining seconds as "Xh Ym"
_fmt_remaining() {
    local secs=$(( $1 ))
    echo "$(( secs / 3600 ))h $(( (secs % 3600) / 60 ))m"
}

# ── lxplus (Kerberos) ────────────────────────────────────────
_header "lxplus / CERN (Kerberos)"
if command -v klist &>/dev/null; then
    KLIST=$(klist 2>&1)
    if echo "$KLIST" | grep -qE "Credentials cache|Ticket cache"; then
        EXPIRY_LINE=$(echo "$KLIST" | grep "krbtgt/CERN.CH" | head -1)
        # macOS Heimdal: "Dec 10 13:38:50 2026  krbtgt/..."  → expiry in fields $1-$4
        # Linux MIT:     "05/12/2026 15:51:12  05/13/2026 15:51:01  krbtgt/..." → expiry in fields $3-$4
        if echo "$EXPIRY_LINE" | grep -qE '^[A-Za-z]{3} '; then
            EXPIRY_RAW=$(echo "$EXPIRY_LINE" | awk '{print $1, $2, $3, $4}')
            EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y" "$EXPIRY_RAW" "+%s" 2>/dev/null || echo "")
        else
            EXPIRY_RAW=$(echo "$EXPIRY_LINE" | awk '{print $3, $4}')
            EXPIRY_EPOCH=$(date -d "$EXPIRY_RAW" "+%s" 2>/dev/null || echo "")
        fi
        NOW_EPOCH=$(date "+%s")

        if [[ -n "$EXPIRY_EPOCH" && "$NOW_EPOCH" -lt "$EXPIRY_EPOCH" ]]; then
            EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
            REMAINING=$(_fmt_remaining $(( EXPIRY_EPOCH - NOW_EPOCH )))
            _ok "Valid ticket — expires $EXPIRY_FMT ($REMAINING remaining)"
        else
            EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
            _err "Ticket expired ($EXPIRY_FMT) — run: ssh-remote-auth --host lxplus -u <username>"
        fi

        # $(NF-1) gets the flags field regardless of date format variations across OSes
        FLAGS=$(klist -f 2>/dev/null | grep "krbtgt/CERN.CH" | awk '{print $(NF-1)}' | head -1)
        if echo "$FLAGS" | grep -q "F"; then
            _ok "Ticket is forwardable — credentials will be delegated to lxplus"
        else
            _warn "Ticket is not forwardable — SSH login works but Kerberos"
            _warn "credentials won't be delegated (AFS/EOS on lxplus may be inaccessible)."
            _warn "Check 'forwardable = true' is in your krb5.conf, then re-run: ssh-remote-auth --host lxplus -u <username>"
        fi
    else
        _err "No valid Kerberos ticket — run: ssh-remote-auth --host lxplus -u <username>"
    fi
else
    _warn "klist not found — Kerberos tools may not be installed"
fi

# ── NERSC (sshproxy certificate) ─────────────────────────────
_header "NERSC (sshproxy certificate)"
NERSC_CERT="$HOME/.ssh/nersc-cert.pub"
if [[ -f "$NERSC_CERT" ]]; then
    EXPIRY_RAW=$(ssh-keygen -L -f "$NERSC_CERT" 2>/dev/null | awk '/Valid:/{print $NF}')
    EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$EXPIRY_RAW" "+%s" 2>/dev/null \
        || date -d "$EXPIRY_RAW" "+%s" 2>/dev/null || echo "")
    NOW_EPOCH=$(date "+%s")
    if [[ -n "$EXPIRY_EPOCH" && "$NOW_EPOCH" -lt "$EXPIRY_EPOCH" ]]; then
        EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
        REMAINING=$(_fmt_remaining $(( EXPIRY_EPOCH - NOW_EPOCH )))
        _ok "Valid certificate — expires $EXPIRY_FMT ($REMAINING remaining)"
    else
        EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
        _err "Certificate expired ($EXPIRY_FMT) — run: ssh-remote-auth --host nersc -u <username>"
    fi
else
    _err "No certificate found at $NERSC_CERT — run: ssh-remote-auth --host nersc -u <username>"
fi

# ── LRC / Lawrencium (SSH certificate) ───────────────────────
_header "LRC / Lawrencium (SSH certificate)"
LRC_CERT="$HOME/.ssh/ssh_certs/lrc_cert-cert.pub"
LRC_KEY="$HOME/.ssh/ssh_certs/lrc_cert"
if [[ -f "$LRC_CERT" ]]; then
    EXPIRY_RAW=$(ssh-keygen -L -f "$LRC_CERT" 2>/dev/null | awk '/Valid:/{print $NF}')
    EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$EXPIRY_RAW" "+%s" 2>/dev/null \
        || date -d "$EXPIRY_RAW" "+%s" 2>/dev/null || echo "")
    NOW_EPOCH=$(date "+%s")
    if [[ -n "$EXPIRY_EPOCH" && "$NOW_EPOCH" -lt "$EXPIRY_EPOCH" ]]; then
        EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
        REMAINING=$(_fmt_remaining $(( EXPIRY_EPOCH - NOW_EPOCH )))
        _ok "Valid certificate — expires $EXPIRY_FMT ($REMAINING remaining)"
    else
        EXPIRY_FMT=$(_fmt_date "$EXPIRY_EPOCH")
        _err "Certificate expired ($EXPIRY_FMT) — run: ssh-remote-auth --host lrc"
    fi
elif [[ -f "$LRC_KEY" ]]; then
    _warn "Key found but no certificate at $LRC_CERT — run: ssh-remote-auth --host lrc"
else
    _err "No key or certificate found — run: ssh-remote-auth --host lrc"
fi

# ── S3DF / SLAC (SSH key) ─────────────────────────────────────
_header "S3DF / SLAC (SSH key)"
S3DF_KEY="$HOME/.ssh/s3df/key"
if [[ -f "$S3DF_KEY" ]]; then
    MTIME=$(stat -f "%m" "$S3DF_KEY" 2>/dev/null || stat -c "%Y" "$S3DF_KEY" 2>/dev/null)
    CREATED=$(_fmt_date "$MTIME")
    _ok "Key present — created $CREATED"
    _warn "S3DF keys expire periodically — re-register at https://s3df-sshkeys.slac.stanford.edu if login fails"
else
    _err "No key found at $S3DF_KEY — run: ssh-remote-auth --host s3df -u <username>"
fi

echo
