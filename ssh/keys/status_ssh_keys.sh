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

# ── lxplus (Kerberos) ────────────────────────────────────────
_header "lxplus / CERN (Kerberos)"
if command -v klist &>/dev/null; then
    KLIST=$(klist 2>&1)
    if echo "$KLIST" | grep -q "Credentials cache"; then
        EXPIRY=$(echo "$KLIST" | grep "krbtgt/CERN.CH" | awk '{print $3, $4}' | head -1)
        FLAGS=$(klist -f 2>/dev/null | grep "krbtgt/CERN.CH" | awk '{print $1}' | head -1)
        _ok "Valid ticket — expires $EXPIRY"
        if echo "$FLAGS" | grep -q "F"; then
            _ok "Ticket is forwardable (F flag set)"
        else
            _warn "Ticket is NOT forwardable — re-run setup_lxplus_key.sh"
        fi
    else
        _err "No valid Kerberos ticket — run: ./setup_ssh_key.sh --host lxplus -u <username>"
    fi
else
    _warn "klist not found — Kerberos tools may not be installed"
fi

# ── NERSC (sshproxy certificate) ─────────────────────────────
_header "NERSC (sshproxy certificate)"
NERSC_CERT="$HOME/.ssh/nersc-cert.pub"
if [[ -f "$NERSC_CERT" ]]; then
    VALIDITY=$(ssh-keygen -L -f "$NERSC_CERT" 2>/dev/null | grep "Valid:")
    # Extract the expiry date from "Valid: from ... to YYYY-MM-DDTHH:MM:SS"
    EXPIRY=$(echo "$VALIDITY" | sed 's/.*to //')
    EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$EXPIRY" "+%s" 2>/dev/null \
        || date -d "$EXPIRY" "+%s" 2>/dev/null || echo "")
    NOW_EPOCH=$(date "+%s")
    if [[ -n "$EXPIRY_EPOCH" && "$NOW_EPOCH" -lt "$EXPIRY_EPOCH" ]]; then
        REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 3600 ))
        _ok "Valid certificate — expires $EXPIRY (${REMAINING}h remaining)"
    else
        _err "Certificate expired ($EXPIRY) — run: ./setup_ssh_key.sh --host nersc -u <username>"
    fi
else
    _err "No certificate found at $NERSC_CERT — run: ./setup_ssh_key.sh --host nersc -u <username>"
fi

# ── LRC / Lawrencium (SSH certificate) ───────────────────────
_header "LRC / Lawrencium (SSH certificate)"
LRC_CERT="$HOME/.ssh/ssh_certs/lrc_cert-cert.pub"
LRC_KEY="$HOME/.ssh/ssh_certs/lrc_cert"
if [[ -f "$LRC_CERT" ]]; then
    VALIDITY=$(ssh-keygen -L -f "$LRC_CERT" 2>/dev/null | grep "Valid:")
    EXPIRY=$(echo "$VALIDITY" | sed 's/.*to //')
    EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$EXPIRY" "+%s" 2>/dev/null \
        || date -d "$EXPIRY" "+%s" 2>/dev/null || echo "")
    NOW_EPOCH=$(date "+%s")
    if [[ -n "$EXPIRY_EPOCH" && "$NOW_EPOCH" -lt "$EXPIRY_EPOCH" ]]; then
        REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 3600 ))
        _ok "Valid certificate — expires $EXPIRY (${REMAINING}h remaining)"
    else
        _err "Certificate expired ($EXPIRY) — run: ./setup_ssh_key.sh --host lrc"
    fi
elif [[ -f "$LRC_KEY" ]]; then
    _warn "Key found but no certificate at $LRC_CERT — run: ./setup_ssh_key.sh --host lrc"
else
    _err "No key or certificate found — run: ./setup_ssh_key.sh --host lrc"
fi

# ── S3DF / SLAC (SSH key) ─────────────────────────────────────
_header "S3DF / SLAC (SSH key)"
S3DF_KEY="$HOME/.ssh/s3df/key"
if [[ -f "$S3DF_KEY" ]]; then
    CREATED=$(date -r "$S3DF_KEY" "+%Y-%m-%d %H:%M" 2>/dev/null || stat -c "%y" "$S3DF_KEY" 2>/dev/null)
    _ok "Key present — created $CREATED"
    _warn "S3DF keys expire periodically — re-register at https://s3df-sshkeys.slac.stanford.edu if login fails"
else
    _err "No key found at $S3DF_KEY — run: ./setup_ssh_key.sh --host s3df -u <username>"
fi

echo
