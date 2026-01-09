#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$1"
}

require_mise() {
  if ! command -v mise >/dev/null 2>&1; then
    log "mise is not installed in the container."
    exit 1
  fi
}

ensure_mise_data_dir() {
  if [[ -d "/mnt/mise-data" ]]; then
    if [[ "$(id -u)" == "0" ]]; then
      chown -R "$(id -u):$(id -g)" /mnt/mise-data
    elif command -v sudo >/dev/null 2>&1; then
      sudo chown -R "$(id -u):$(id -g)" /mnt/mise-data
    else
      log "Skipping /mnt/mise-data ownership update (no sudo)."
    fi
  fi
}

maybe_trust_repo() {
  if [[ -f "mise.toml" || -f ".mise.toml" ]]; then
    mise trust .
  fi
}

ensure_shell_hook() {
  local shell_rc="$1"
  local hook_line="$2"

  touch "$shell_rc"
  if ! grep -Fqs "$hook_line" "$shell_rc"; then
    printf '\n%s\n' "$hook_line" >> "$shell_rc"
  fi
}

main() {
  require_mise
  ensure_mise_data_dir
  maybe_trust_repo
  ensure_shell_hook "$HOME/.bashrc" 'eval "$(mise activate bash)"'
  ensure_shell_hook "$HOME/.zshrc" 'eval "$(mise activate zsh)"'
}

main "$@"
