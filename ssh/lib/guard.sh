#!/usr/bin/env bash
# lib/guard.sh — shared re-exec guard
#
# Prevents exit calls and set -e failures from terminating the parent
# shell when a script is sourced instead of run directly.
#
# Usage: add these two lines to the top of any script (before set -euo pipefail):
#
#   _SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
#   source "$(dirname "$_SCRIPT_PATH")/../lib/guard.sh"
#
# How it works: if the script is being sourced (detected via BASH_SOURCE
# in bash, or ZSH_EVAL_CONTEXT in zsh), it re-execs itself as a proper
# subprocess under bash and returns the exit code to the caller.
# When run directly the guard is a no-op.

_is_sourced=0
[[ -n "${BASH_VERSION:-}" && "${_SCRIPT_PATH:-}" != "${0}" ]] && _is_sourced=1
[[ -n "${ZSH_VERSION:-}"  && "${ZSH_EVAL_CONTEXT:-}" == *file* ]] && _is_sourced=1

if [[ $_is_sourced -eq 1 ]]; then
    bash "${_SCRIPT_PATH}" "$@"
    return $?
fi

unset _is_sourced _SCRIPT_PATH
