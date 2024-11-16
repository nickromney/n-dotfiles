# shellcheck shell=zsh

#
# History
#
HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000
setopt inc_append_history

#
# Environment
#
export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"

#
# Tools & Completions
#
# Initialize completions
autoload -Uz compinit && compinit

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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

#
# Aliases
#
alias gs='git status'
alias gc='git commit'

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


