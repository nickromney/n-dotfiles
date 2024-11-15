eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"

HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000

setopt inc_append_history

# initialise completions with ZSH's compinit
autoload -Uz compinit && compinit

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

source $HOME/.local/bin/env

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"                                       # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion

eval "$(uv generate-shell-completion zsh)"
eval "$(uvx generate-shell-completion zsh)"

# Aliases
alias gs='git status'
alias gc='git commit'

# PATH additions
if ! echo $PATH | grep -q "$HOME/.local/bin"; then
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! echo $PATH | grep -q "$HOME/.arkade/bin"; then
  export PATH="$HOME/.arkade/bin:$PATH"
fi

if ! echo $PATH | grep -q "$HOME/.tfenv/bin"; then
  export PATH="$HOME/.tfenv/bin:$PATH"
fi

# PATH de-dup
export PATH=$(echo $PATH | awk -v RS=: '!a[$0]++' | tr "\n" ":")
