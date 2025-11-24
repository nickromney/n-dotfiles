# shellcheck shell=zsh

#
# History
#
# set the location and filename of the history file
export HISTFILE="$HOME/.zsh_history"

# set the maximum number of lines to be saved in the history file
export HISTSIZE="100000"
export SAVEHIST="$HISTSIZE"
# enable comments "#" expressions in the prompt shell
setopt INTERACTIVE_COMMENTS
# append new history entries to the history file
setopt APPEND_HISTORY
# save each command to the history file as soon as it is executed
setopt INC_APPEND_HISTORY
# ignore recording duplicate consecutive commands in the history
setopt HIST_IGNORE_DUPS
# ignore commands that start with a space in the history
setopt HIST_IGNORE_SPACE

#
# Environment
#
export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"
export LANG="en_GB.UTF-8"
export WORDCHARS="" # Specify word boundaries for command line navigation

# Word navigation
if [[ "$OSTYPE" == "darwin"* ]]; then
  bindkey "^[^[[C" forward-word  # Option + Right
  bindkey "^[^[[D" backward-word # Option + Left
else
  bindkey "^[[1;5C" forward-word  # Ctrl + Right
  bindkey "^[[1;5D" backward-word # Ctrl + Left
fi

# Line navigation
bindkey "^A" beginning-of-line   # Ctrl + A
bindkey "^E" end-of-line         # Ctrl + E
bindkey "^[[H" beginning-of-line # Home
bindkey "^[[F" end-of-line       # End

# History search
bindkey "^[[A" history-beginning-search-backward # Up arrow
bindkey "^[[B" history-beginning-search-forward  # Down arrow

#
# Tools & Completions
#
# -Uz ensures that compinit is loaded as a pure function according
#  to zsh's standards, without interference from any aliases defined.
#  Then executes it with the -i flag to ignore insecure files.
autoload -Uz compinit && compinit -i

# Azure CLI completion
if command -v brew >/dev/null 2>&1 && command -v az >/dev/null 2>&1; then
  autoload bashcompinit && bashcompinit
  AZ_COMPLETION="$(brew --prefix)/etc/bash_completion.d/az"
  [ -f "$AZ_COMPLETION" ] && source "$AZ_COMPLETION"
fi

# kubectl completion and aliases
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion zsh)
  # shellcheck disable=SC1091
  DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/n-dotfiles}"
  source "$DOTFILES_DIR/scripts/kubectl-aliases.sh"
  # In zsh, use compdef instead of bash's complete
  compdef _kubectl k
fi

# Local environment will be sourced later in the file

# Completion menu
zstyle ':completion:*:*:*:*:*' menu select
bindkey '^[[Z' reverse-menu-complete

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Rbenv
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init -)"
fi

# Zoxide
ZOXIDE_AVAILABLE=false
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
  ZOXIDE_AVAILABLE=true
fi

# FZF configuration
FZF_AVAILABLE=false
if command -v fzf >/dev/null 2>&1; then
  FZF_AVAILABLE=true
  # Only source fzf completion if it exists
  if FZF_COMPLETION=$(fzf --zsh 2>/dev/null); then
    source <(echo "$FZF_COMPLETION")
  fi

  export FZF_DEFAULT_OPTS="--height 100% --layout reverse --preview-window=wrap"
  export FZF_CTRL_R_OPTS="--preview 'echo {}'"

  # Only set FD command if fd/find is available
  if command -v fd >/dev/null 2>&1; then
    export FZF_CTRL_T_COMMAND="fd --exclude .git --hidden --follow"
  fi

  # Preview file content using bat (if available)
  if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
      --walker-skip .git,node_modules,target
      --preview 'bat -n --color=always {}'
      --bind 'ctrl-/:change-preview-window(down|hidden|)'"
  fi
fi

# UV tools
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion zsh)"
fi

#
# Plugin Management
#
if command -v brew >/dev/null 2>&1; then
  ZSH_AUTOSUGGESTIONS="$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_SYNTAX_HIGHLIGHTING="$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

  [ -f "$ZSH_AUTOSUGGESTIONS" ] && source "$ZSH_AUTOSUGGESTIONS"
  [ -f "$ZSH_SYNTAX_HIGHLIGHTING" ] && source "$ZSH_SYNTAX_HIGHLIGHTING"
fi

#
# FNM Setup (Fast Node Manager)
#
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd)"
fi

#
# Local Environment
#
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

# ZScaler Certs
ZSCALER_CERT_DIR="$HOME/.zscalerCerts"
if [ -d "$ZSCALER_CERT_DIR" ]; then
  ZSCALER_CA_BUNDLE="$ZSCALER_CERT_DIR/zscalerCAbundle.pem"
  AZURE_CA_CERT="$ZSCALER_CERT_DIR/azure-cacert.pem"

  # Only set environment variables if certificate files exist
  [ -f "$ZSCALER_CA_BUNDLE" ] && export AWS_CA_BUNDLE="$ZSCALER_CA_BUNDLE"
  [ -f "$ZSCALER_CA_BUNDLE" ] && export CURL_CA_BUNDLE="$ZSCALER_CA_BUNDLE"
  [ -f "$ZSCALER_CA_BUNDLE" ] && export GIT_SSL_CAPATH="$ZSCALER_CA_BUNDLE"
  [ -f "$ZSCALER_CA_BUNDLE" ] && export NODE_EXTRA_CA_CERTS="$ZSCALER_CA_BUNDLE"
  [ -f "$AZURE_CA_CERT" ] && export REQUESTS_CA_BUNDLE="$AZURE_CA_CERT"
  [ -f "$ZSCALER_CA_BUNDLE" ] && export SSL_CERT_FILE="$ZSCALER_CA_BUNDLE"
fi

#
# 1Password SSH Agent Setup
#
if command -v op >/dev/null 2>&1; then
  # 1Password CLI is installed
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    OP_SOCKET_PATH="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [ -S "$OP_SOCKET_PATH" ]; then
      # Create ~/.1password directory if it doesn't exist
      mkdir -p "$HOME/.1password"
      # Create symlink for easier access if it doesn't exist or is broken
      if [ ! -L "$HOME/.1password/agent.sock" ] || [ ! -e "$HOME/.1password/agent.sock" ]; then
        ln -sf "$OP_SOCKET_PATH" "$HOME/.1password/agent.sock"
      fi
      # Set the environment variable
      export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
    fi
  else
    # Linux
    OP_SOCKET_PATH="$HOME/.1password/agent.sock"
    if [ -S "$OP_SOCKET_PATH" ]; then
      export SSH_AUTH_SOCK="$OP_SOCKET_PATH"
    fi
  fi
fi

#
# PATH Management
#
declare -a paths=(
  "$HOME/.local/bin"
  "$HOME/.arkade/bin"
  "$HOME/.cargo/bin"
  "$HOME/.lmstudio/bin"
  "$HOME/.tfenv/bin"
)

for path_entry in "${paths[@]}"; do
  if [ -d "$path_entry" ] && ! echo "$PATH" | grep -q "$path_entry"; then
    export PATH="$path_entry:$PATH"
  fi
done

# De-duplicate PATH and remove empty entries
PATH=$(echo "$PATH" | awk -v RS=: '!a[$0]++' | grep -v '^$' | paste -sd: -)
export PATH

# Podman socket for Docker compatibility
if command -v podman >/dev/null 2>&1; then
  if PODMAN_SOCKET=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null) && [ -n "$PODMAN_SOCKET" ]; then
    export DOCKER_HOST="unix://$PODMAN_SOCKET"
  fi
fi

#
# Aliases
#
# Add aliases at the end after all tools are initialized

# Navigation aliases - conditionally created based on available tools
DEVELOPER_DIR="$HOME/Developer"
if $ZOXIDE_AVAILABLE; then
  # If zoxide is available, use it for navigation
  alias o="z"

  # Only create cdd if the Developer directory exists
  if [ -d "$DEVELOPER_DIR" ]; then
    alias cdd='z "$HOME/Developer"'
  fi
else
  # Fallback if zoxide is not available
  if [ -d "$DEVELOPER_DIR" ]; then
    alias cdd='cd "$HOME/Developer"'
  fi
fi

# Git aliases
if command -v git >/dev/null 2>&1; then
  alias gs='git status'
  alias gc='git commit'

  # Only add lazygit alias if it's available
  if command -v lazygit >/dev/null 2>&1; then
    alias g="lazygit"
    alias lg="lazygit"
  fi
fi

# Docker/Container aliases
if command -v lazydocker >/dev/null 2>&1; then
  alias d="lazydocker"
  alias ld="lazydocker"
fi

# File listing aliases
if command -v eza >/dev/null 2>&1; then
  alias e="eza"
  alias l="eza --oneline"
  alias tree="eza --tree"
else
  alias l="ls -1"
fi
alias ll="ls -al"

# Editor aliases
if command -v nvim >/dev/null 2>&1; then
  alias n="nvim"
fi

# FZF combination aliases - only if required tools are available
if $FZF_AVAILABLE; then
  alias f="fzf"

  if command -v bat >/dev/null 2>&1; then
    alias bf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | xargs bat"

    if command -v nvim >/dev/null 2>&1; then
      alias nf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | xargs nvim"
    fi

    if command -v pbcopy >/dev/null 2>&1; then
      alias pf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | pbcopy"
    fi
  fi
fi

# Utility aliases
alias sz="source ~/.zshrc"

# AWS Lambda virtual environment alias - check if directory exists first
AWS_LAMBDA_VENV="$HOME/.venvs/aws-lambda/bin/activate"
if [ -f "$AWS_LAMBDA_VENV" ]; then
  alias aws-lambda-env='source "$AWS_LAMBDA_VENV"'
fi

# direnv integration
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

