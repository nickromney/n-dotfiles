#!/usr/bin/env bash
# Restarts slicer-mac services (tray and/or daemon).
# Defaults to dry-run mode; pass --execute to actually restart.
# Defaults to both services; pass --tray or --daemon to target one only.
#
# Usage:
#   restart-slicer-mac.sh [--execute] [--tray] [--daemon]
#
# Restart order:
#   1. Report current service status for selected services
#   2. slicer-mac service restart tray   (if selected)
#   3. slicer-mac service restart daemon (if selected)

set -euo pipefail

DRY_RUN=true
DO_TRAY=false
DO_DAEMON=false

for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    --tray)    DO_TRAY=true ;;
    --daemon)  DO_DAEMON=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Default: both services
if ! "$DO_TRAY" && ! "$DO_DAEMON"; then
  DO_TRAY=true
  DO_DAEMON=true
fi

# Check slicer-mac is available
if ! command -v slicer-mac &>/dev/null; then
  echo "Error: slicer-mac not found in PATH." >&2
  exit 1
fi

# Phase 0: Status report
echo "==> slicer-mac service status:"
if "$DO_TRAY";   then slicer-mac service status tray   || true; fi
if "$DO_DAEMON"; then slicer-mac service status daemon || true; fi
echo ""

if "$DRY_RUN"; then
  echo "[dry-run] Would run:"
  if "$DO_TRAY";   then echo "  slicer-mac service restart tray"; fi
  if "$DO_DAEMON"; then echo "  slicer-mac service restart daemon"; fi
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
