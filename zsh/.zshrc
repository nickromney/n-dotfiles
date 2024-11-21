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
# Aliases
#
alias cdd='cd "$HOME/Developer"'
alias f="fzf"
alias g="lazygit"
alias gs='git status'
alias gc='git commit'
alias l="eza --oneline"
alias ll="ls -al"
alias n="nvim"
alias o="z"
alias cd="z"
alias bf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | xargs bat"
alias nf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | xargs nvim"
alias pf="fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | pbcopy"
alias sz="source ~/.zshrc"
alias tree="eza --tree"
#
# Tools & Completions
#
# Initialize completions
autoload -Uz compinit && compinit

[ -f "$HOME/.zsh/aliases.zsh" ] && source "$HOME/.local/bin/env"

# Completion menu
zstyle ':completion:*:*:*:*:*' menu select
bindkey '^[[Z' reverse-menu-complete

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# FZF configuration
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="--height 100% --layout reverse --preview-window=wrap"
  export FZF_CTRL_R_OPTS="--preview 'echo {}'"
  export FZF_CTRL_T_COMMAND="fd --exclude .git --hidden --follow"
  # Preview file content using bat (https://github.com/sharkdp/bat)
  export FZF_CTRL_T_OPTS="
    --walker-skip .git,node_modules,target
    --preview 'bat -n --color=always {}'
    --bind 'ctrl-/:change-preview-window(down|hidden|)'"
fi

# UV tools
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion zsh)"
fi

#
# Plugin Management
#
ZSH_AUTOSUGGESTIONS="/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
ZSH_SYNTAX_HIGHLIGHTING="/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

[ -f "$ZSH_AUTOSUGGESTIONS" ] && source "$ZSH_AUTOSUGGESTIONS"
[ -f "$ZSH_SYNTAX_HIGHLIGHTING" ] && source "$ZSH_SYNTAX_HIGHLIGHTING"

#
# NVM Setup
#
if command -v brew >/dev/null 2>&1 && [ -d "$(brew --prefix nvm)" ]; then
  export NVM_DIR="$HOME/.nvm"
  NVM_SCRIPT="$(brew --prefix nvm)/nvm.sh"
  NVM_COMPLETION="$(brew --prefix nvm)/etc/bash_completion.d/nvm"

  [ -s "$NVM_SCRIPT" ] && source "$NVM_SCRIPT"
  [ -s "$NVM_COMPLETION" ] && source "$NVM_COMPLETION"
fi

#
# Local Environment
#
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

# ZScaler Certs
if [ -d "$HOME/.zscalerCerts" ]; then
  export AWS_CA_BUNDLE="$HOME/.zscalerCerts/zscalerCAbundle.pem"
  export CURL_CA_BUNDLE="$HOME/.zscalerCerts/zscalerCAbundle.pem"
  export GIT_SSL_CAPATH="$HOME/.zscalerCerts/zscalerCAbundle.pem"
  export NODE_EXTRA_CA_CERTS="$HOME/.zscalerCerts/zscalerCAbundle.pem"
  export REQUESTS_CA_BUNDLE="$HOME/.zscalerCerts/azure-cacert.pem"
  export SSL_CERT_FILE="$HOME/.zscalerCerts/zscalerCAbundle.pem"
fi

#
# PATH Management
#
declare -a paths=(
  "$HOME/.local/bin"
  "$HOME/.arkade/bin"
  "$HOME/.tfenv/bin"
)

for path_entry in "${paths[@]}"; do
  if [ -d "$path_entry" ] && ! echo $PATH | grep -q "$path_entry"; then
    export PATH="$path_entry:$PATH"
  fi
done

# De-duplicate PATH
export PATH=$(echo $PATH | awk -v RS=: '!a[$0]++' | tr "\n" ":")
