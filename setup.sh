#!/usr/bin/env bash

# Resolve the path of this file correctly in both bash and zsh.
# bash: BASH_SOURCE[0] is always the sourced file path.
# zsh:  ${(%):-%x} gives the sourced file path regardless of $0 or
#       POSIX_ARGZERO; eval prevents bash from choking on zsh syntax.
if [[ -n "${ZSH_VERSION:-}" ]]; then
    eval '_setup_file="${(%):-%x}"'
else
    _setup_file="${BASH_SOURCE[0]}"
fi
DOTFILES_DIR="$(cd "$(dirname "$_setup_file")" && pwd)"
unset _setup_file

SSH_REMOTE_CONFIG_SCRIPT="$DOTFILES_DIR/ssh/config/setup_ssh_configs.sh"
SSH_REMOTE_AUTH_SCRIPT="$DOTFILES_DIR/ssh/keys/setup_ssh_key.sh"
SSH_REMOTE_STATUS_SCRIPT="$DOTFILES_DIR/ssh/keys/status_ssh_keys.sh"

if [[ ! -f "$SSH_REMOTE_CONFIG_SCRIPT" || ! -f "$SSH_REMOTE_AUTH_SCRIPT" || ! -f "$SSH_REMOTE_STATUS_SCRIPT" ]]; then
    printf 'setup.sh: could not locate expected ssh scripts under "%s"\n' "$DOTFILES_DIR" >&2
    return 1 2>/dev/null || exit 1
fi

chmod +x "$SSH_REMOTE_CONFIG_SCRIPT" "$SSH_REMOTE_AUTH_SCRIPT" "$SSH_REMOTE_STATUS_SCRIPT"

alias ssh-remote-config="bash '$SSH_REMOTE_CONFIG_SCRIPT'"
alias ssh-remote-auth="bash '$SSH_REMOTE_AUTH_SCRIPT'"
alias ssh-remote-status="bash '$SSH_REMOTE_STATUS_SCRIPT'"
