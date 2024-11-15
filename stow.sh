#!/bin/bash
set -euo pipefail

if ! command -v stow &>/dev/null; then
  echo "stow is not installed. Please install stow first."
  echo "Check instructions at https://www.gnu.org/software/stow/"
  exit 1
fi

stow stow

stow_array=(amethyst bat gh git karabiner kitty nvim ssh starship tmux zsh)

for dir in "${stow_array[@]}"; do
  if stow -v -R -t "$HOME" "$dir"; then
    echo "Stowed $dir"
  else
    echo "Error stowing $dir"
  fi
done
