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

main() {
  require_mise

  if [[ -f "mise.toml" || -f ".mise.toml" ]]; then
    log "Installing tools with mise..."
    mise install
  else
    log "No mise.toml found, skipping tool install."
  fi
}

main "$@"
