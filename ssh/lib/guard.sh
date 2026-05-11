#!/usr/bin/env bash
# lib/guard.sh — shared re-exec guard
#
# Prevents exit calls and set -e failures from terminating the parent
# shell when a script is sourced instead of run directly.
#
# Add these three lines to the top of any setup script, before set -euo pipefail:
#
#   source "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/../lib/guard.sh"
#   [[ ${_GUARD_DID_REEXEC:-0} -eq 1 ]] && { _rc=${_GUARD_RC:-0}; unset _GUARD_DID_REEXEC _GUARD_RC; return "$_rc"; }
#   unset _GUARD_DID_REEXEC _GUARD_RC
#
# Why three lines?
# return inside guard.sh only returns to the calling script, not from it.
# The second line checks the flag guard.sh sets and issues the return that
# actually stops the calling script from continuing in the parent shell.
# The third line cleans up when the script is run directly (flag is 0).
#
# How caller path is resolved:
#   bash: BASH_SOURCE[1] — the file that sourced guard.sh
#   zsh:  funcfiletrace[1] — "filepath:lineno" of the source call; line
#         number is stripped with %:*. eval is used so that bash does not
#         choke on zsh-specific parameter expansion syntax at parse time.

_GUARD_DID_REEXEC=0
_GUARD_RC=0
_guard_caller=""
_guard_is_sourced=0

if [[ -n "${BASH_VERSION:-}" ]]; then
    _guard_caller="${BASH_SOURCE[1]:-}"
    [[ -n "$_guard_caller" && "$_guard_caller" != "${0}" ]] && _guard_is_sourced=1

elif [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ "${ZSH_EVAL_CONTEXT:-}" == *file* ]] && _guard_is_sourced=1
    # funcfiletrace is zsh-specific; eval prevents bash parse errors on
    # the nested parameter expansion when this file is read by bash.
    [[ $_guard_is_sourced -eq 1 ]] && eval '_guard_caller="${funcfiletrace[1]%:*}"'
fi

if [[ $_guard_is_sourced -eq 1 ]]; then
    if [[ -z "$_guard_caller" || ! -f "$_guard_caller" ]]; then
        echo "guard.sh: cannot re-exec: caller path '${_guard_caller}' is missing or not a file" >&2
        unset _guard_caller _guard_is_sourced
        return 1
    fi
    command bash -- "$_guard_caller" "$@"
    _GUARD_RC=$?
    _GUARD_DID_REEXEC=1
fi

unset _guard_caller _guard_is_sourced
