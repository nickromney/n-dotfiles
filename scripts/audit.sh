#!/usr/bin/env bash
set -euo pipefail

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit.sh [options]

Run the installed-tools audit and write a timestamped report under `_audit/installed/`.

Options:
  -h, --help               Show this help message
  -o, --out-base <path>    Base directory for audit output

Examples:
  scripts/audit.sh
  scripts/audit.sh --out-base /tmp/n-dotfiles-audit
EOF

  exit "$exit_code"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

exec "$SCRIPT_DIR/audit-installed.sh" "$@"
