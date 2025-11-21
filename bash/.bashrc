# shellcheck shell=bash

#
# History
#
export HISTFILE="$HOME/.bash_history"
export HISTSIZE=100000
export HISTFILESIZE=$HISTSIZE
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend  # Append to history, don't overwrite

#
# Shell Options
#
shopt -s globstar    # Enable ** recursive glob
shopt -s nullglob    # Null globs expand to nothing
shopt -s checkwinsize # Check window size after each command

#
# Environment
#
export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"
export LANG="en_GB.UTF-8"

#
# Homebrew
#
if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ -d "/opt/homebrew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -d "/usr/local/Homebrew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

#
# Starship Prompt
#
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

#
# FNM Setup (Fast Node Manager)
#
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd)"
fi

#
# PATH Management
#
paths=(
  "$HOME/.local/bin"
  "$HOME/.arkade/bin"
  "$HOME/.cargo/bin"
  "$HOME/.tfenv/bin"
)

for path_entry in "${paths[@]}"; do
  if [ -d "$path_entry" ] && ! echo "$PATH" | grep -q "$path_entry"; then
    export PATH="$path_entry:$PATH"
  fi
done

# De-duplicate PATH
PATH=$(echo "$PATH" | awk -v RS=: '!a[$0]++' | paste -sd:)
export PATH

#
# kubectl completion and aliases
#
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  # shellcheck disable=SC1091
  DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/n-dotfiles}"
  source "$DOTFILES_DIR/scripts/kubectl-aliases.sh"
  complete -F __start_kubectl k
fi

#
# 1Password SSH Agent
#
if [ -S "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ]; then
  export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
fi

#
# Local Environment
#
# Override any of the above settings in this file
if [ -f "$HOME/.bashrc.local" ]; then
  # shellcheck disable=SC1091
  source "$HOME/.bashrc.local"
fi
