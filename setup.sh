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

# Ensure all scripts are executable
chmod +x "$DOTFILES_DIR/ssh/config"/*.sh "$DOTFILES_DIR/ssh/keys"/*.sh

alias ssh-remote-config="bash '$DOTFILES_DIR/ssh/config/setup_ssh_configs.sh'"
alias ssh-remote-auth="bash '$DOTFILES_DIR/ssh/keys/setup_ssh_key.sh'"
alias ssh-remote-status="bash '$DOTFILES_DIR/ssh/keys/status_ssh_keys.sh'"
