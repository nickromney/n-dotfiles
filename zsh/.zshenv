# ~/.zshenv - Environment variables that should be set for all zsh sessions

# ZSH syntax highlighting configuration
ZSH_HIGHLIGHT_DIR="/opt/homebrew/share/zsh-syntax-highlighting"
if [ -d "$ZSH_HIGHLIGHT_DIR" ]; then
  export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="$ZSH_HIGHLIGHT_DIR/highlighters"
fi
