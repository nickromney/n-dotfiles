#!/usr/bin/env bash
# Build and install the standalone Borders app when its sibling checkout exists.

set -euo pipefail

BORDERS_REPO="${BORDERS_REPO:-$HOME/Developer/personal/borders}"
MAKE_CMD="${BORDERS_MAKE_CMD:-make}"
DRY_RUN=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Build and install the standalone Borders app from its local sibling checkout.
The checkout is optional; a missing checkout is skipped without error.

Options:
  -d, --dry-run  Show what would happen without building or installing
  -h, --help     Show this help message

Environment:
  BORDERS_REPO      Checkout path (default: $HOME/Developer/personal/borders)
  BORDERS_MAKE_CMD  Make command (default: make)

Examples:
  $0
  $0 --dry-run
  BORDERS_REPO=~/src/borders $0
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      error "Unknown option: $1"
      usage 1
      ;;
  esac
done

if [[ ! -d "$BORDERS_REPO" ]]; then
  echo "Skipping Borders installation: checkout not found at $BORDERS_REPO"
  exit 0
fi

if [[ ! -f "$BORDERS_REPO/Makefile" ]]; then
  error "Borders checkout has no Makefile: $BORDERS_REPO"
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  printf '[dry-run] Would execute:'
  printf ' %q' "$MAKE_CMD" -C "$BORDERS_REPO" install
  printf '\n'
  exit 0
fi

if ! command -v "$MAKE_CMD" >/dev/null 2>&1; then
  error "Make command not found: $MAKE_CMD"
  exit 1
fi

echo "Installing Borders from $BORDERS_REPO"
"$MAKE_CMD" -C "$BORDERS_REPO" install
