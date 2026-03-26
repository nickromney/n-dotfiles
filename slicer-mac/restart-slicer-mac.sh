#!/usr/bin/env bash
# Restarts slicer-mac services.
# Defaults to dry-run mode; pass --execute to actually restart.

set -euo pipefail

DRY_RUN=true
DO_TRAY=false
DO_DAEMON=false

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: slicer-mac/restart-slicer-mac.sh [options]

Restart the slicer-mac tray service, daemon, or both.
This script defaults to dry-run mode.

Options:
      --daemon   Restart only the daemon service
  -d, --dry-run  Preview the restart commands without running them
      --execute  Restart the selected services for real
  -h, --help     Show this help message
      --tray     Restart only the tray service

Examples:
  slicer-mac/restart-slicer-mac.sh
  slicer-mac/restart-slicer-mac.sh --execute
  slicer-mac/restart-slicer-mac.sh --execute --daemon
EOF

  exit "$exit_code"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --execute)
        DRY_RUN=false
        shift
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      --tray)
        DO_TRAY=true
        shift
        ;;
      --daemon)
        DO_DAEMON=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if ! "$DO_TRAY" && ! "$DO_DAEMON"; then
    DO_TRAY=true
    DO_DAEMON=true
  fi

  if ! command -v slicer-mac &>/dev/null; then
    echo "Error: slicer-mac not found in PATH." >&2
    exit 1
  fi

  echo "==> slicer-mac service status:"
  if "$DO_TRAY"; then
    slicer-mac service status tray || true
  fi
  if "$DO_DAEMON"; then
    slicer-mac service status daemon || true
  fi
  echo ""

  if "$DRY_RUN"; then
    echo "[dry-run] Would run:"
    if "$DO_TRAY"; then
      echo "  slicer-mac service restart tray"
    fi
    if "$DO_DAEMON"; then
      echo "  slicer-mac service restart daemon"
    fi
    echo ""
    echo "Pass --execute to restart."
    exit 0
  fi

  echo "Restarting..."

  if "$DO_TRAY"; then
    echo "  slicer-mac service restart tray"
    slicer-mac service restart tray
  fi

  if "$DO_DAEMON"; then
    echo "  slicer-mac service restart daemon"
    slicer-mac service restart daemon
  fi

  echo ""
  echo "Done."
}

main "$@"
