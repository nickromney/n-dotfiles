#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-with-policy.sh <brew arguments...>

Runs brew with the repository's Homebrew tap trust policy.

The adapter suppresses repeated environment hints. Non-official Brewfile
entries are trusted explicitly by scripts/brew-trust.sh before bundle and
update operations.

Policy:
  HOMEBREW_NO_ENV_HINTS=1 is applied to reduce repeated policy hints.

Examples:
  scripts/brew-with-policy.sh update
  scripts/brew-with-policy.sh upgrade --cask
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

exec env HOMEBREW_NO_ENV_HINTS=1 brew "$@"
