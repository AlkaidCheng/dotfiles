#!/usr/bin/env bash
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Ensure all scripts are executable
chmod +x "$DOTFILES_DIR/ssh/config"/*.sh "$DOTFILES_DIR/ssh/keys"/*.sh

alias ssh-remote-config="bash '$DOTFILES_DIR/ssh/config/setup_ssh_configs.sh'"
alias ssh-remote-auth="bash '$DOTFILES_DIR/ssh/keys/setup_ssh_key.sh'"
alias ssh-remote-status="bash '$DOTFILES_DIR/ssh/keys/status_ssh_keys.sh'"
