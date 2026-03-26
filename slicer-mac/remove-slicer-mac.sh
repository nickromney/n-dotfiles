#!/usr/bin/env bash
# Removes slicer-mac installation artifacts.
# Defaults to dry-run mode; pass --execute to actually remove.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=true

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: slicer-mac/remove-slicer-mac.sh [options]

Remove slicer-mac launch agents, bundles, CLI artifacts, caches, and crash files.
This script defaults to dry-run mode.

Options:
  -d, --dry-run  Preview removals without deleting anything
      --execute  Remove slicer artifacts for real
  -h, --help     Show this help message

Examples:
  slicer-mac/remove-slicer-mac.sh
  slicer-mac/remove-slicer-mac.sh --execute
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
  local found_count

  parse_args "$@"

  KILL_PROCS=(
    "slicer-tray"
    "slicer-mac"
  )

  PLIST_SERVICE_LABELS=(
    "com.openfaasltd.slicer-mac"
    "com.openfaasltd.slicer-mac.tray"
  )

  PLIST_PATHS=(
    "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.plist"
    "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.tray.plist"
  )

  SUDO_PATHS=(
    "/usr/local/bin/slicer"
    "/usr/local/bin/openapi.yaml"
  )

  USER_PATHS=(
    "$HOME/slicer"
    "$HOME/slicer-mac"
  )

  ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init"
  ZSH_CACHE_PATHS=(
    "$ZSH_CACHE_DIR/slicer.zsh"
    "$ZSH_CACHE_DIR/slicer-mac.zsh"
  )

  CRASH_REPORTER_DIR="$HOME/Library/Application Support/CrashReporter"
  CRASH_REPORTER_GLOB="slicer-mac_*.plist"

  RUNTIME_DIRS=(
    ".sbox-runtime"
    ".slicer-configdrive"
    ".slicer-power-events"
    "kernel"
    "oci-cache"
  )
  RUNTIME_GLOBS=(
    "slicer*.sock"
    "slicer*.img"
    "slicer*.log"
    "slicer-power.log"
  )

  found_running_procs=()
  found_sudo=()
  found_user=()
  found_plists=()
  found_zsh_cache=()
  found_crash_reporter=()
  found_runtime_wrong=()

  for name in "${KILL_PROCS[@]}"; do
    pgrep -x "$name" &>/dev/null && found_running_procs+=("$name") || true
  done

  for path in "${SUDO_PATHS[@]}"; do
    [[ -e "$path" ]] || [[ -L "$path" ]] && found_sudo+=("$path") || true
  done

  for path in "${USER_PATHS[@]}"; do
    [[ -e "$path" ]] || [[ -L "$path" ]] && found_user+=("$path") || true
  done

  for path in "${PLIST_PATHS[@]}"; do
    [[ -e "$path" ]] || [[ -L "$path" ]] && found_plists+=("$path") || true
  done

  for path in "${ZSH_CACHE_PATHS[@]}"; do
    [[ -f "$path" ]] && found_zsh_cache+=("$path") || true
  done

  for path in "$CRASH_REPORTER_DIR"/$CRASH_REPORTER_GLOB; do
    [[ -e "$path" ]] && found_crash_reporter+=("$path") || true
  done

  if [[ "$SCRIPT_DIR" != "$HOME/slicer-mac" ]] && [[ -d "$SCRIPT_DIR" ]]; then
    for name in "${RUNTIME_DIRS[@]}"; do
      path="$SCRIPT_DIR/$name"
      [[ -e "$path" ]] && found_runtime_wrong+=("$path") || true
    done
    for glob in "${RUNTIME_GLOBS[@]}"; do
      for path in "$SCRIPT_DIR"/$glob; do
        [[ -e "$path" ]] && found_runtime_wrong+=("$path") || true
      done
    done
  fi

  found_count=$(( ${#found_running_procs[@]} + ${#found_sudo[@]} + ${#found_user[@]} + ${#found_plists[@]} + ${#found_zsh_cache[@]} + ${#found_runtime_wrong[@]} + ${#found_crash_reporter[@]} ))

  if [[ $found_count -eq 0 ]]; then
    echo "Nothing to remove - no slicer artifacts found."
    echo ""
    echo "NOTE: Check System Settings -> General -> Login Items & Extensions -> Allow in the Background"
    echo "and remove any remaining slicer-tray entry manually if present."
    exit 0
  fi

  echo "Slicer artifacts found:"
  for name in "${found_running_procs[@]+"${found_running_procs[@]}"}"; do
    echo "  [process]  $name (running)"
  done
  for path in "${found_plists[@]+"${found_plists[@]}"}"; do
    echo "  [plist]    $path"
  done
  for path in "${found_user[@]+"${found_user[@]}"}"; do
    echo "  [user]     $path"
  done
  for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
    echo "  [wrong-dir] $path"
  done
  for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
    echo "  [sudo]     $path"
  done
  for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
    echo "  [cache]    $path"
  done
  for path in "${found_crash_reporter[@]+"${found_crash_reporter[@]}"}"; do
    echo "  [crash]    $path"
  done
  echo ""

  if "$DRY_RUN"; then
    echo "[dry-run] No changes made. Pass --execute to remove."
    echo ""
    echo "NOTE: After running --execute, also check:"
    echo "  System Settings -> General -> Login Items & Extensions -> Allow in the Background"
    echo "  and remove any remaining slicer-tray entry manually."
    exit 0
  fi

  echo "Removing..."

  for name in "${found_running_procs[@]+"${found_running_procs[@]}"}"; do
    echo "  pkill -x $name"
    pkill -x "$name" || true
  done

  for label in "${PLIST_SERVICE_LABELS[@]}"; do
    if launchctl list "$label" &>/dev/null; then
      echo "  launchctl bootout gui/$(id -u)/$label"
      launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    fi
  done
  for path in "${found_plists[@]+"${found_plists[@]}"}"; do
    if [[ -e "$path" ]]; then
      echo "  launchctl unload $path"
      launchctl unload "$path" 2>/dev/null || true
      echo "  rm -f $path"
      rm -f "$path"
    fi
  done

  for path in "${found_user[@]+"${found_user[@]}"}"; do
    echo "  rm -rf $path"
    rm -rf "$path"
  done
  for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
    echo "  rm -rf $path"
    rm -rf "$path"
  done

  for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
    echo "  sudo rm -rf $path"
    sudo rm -rf "$path"
  done

  for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
    echo "  rm -f $path"
    rm -f "$path"
  done
  for path in "${found_crash_reporter[@]+"${found_crash_reporter[@]}"}"; do
    echo "  rm -f $path"
    rm -f "$path"
  done

  echo ""
  echo "Done."
  echo ""
  echo "NOTE: Check System Settings -> General -> Login Items & Extensions -> Allow in the Background"
  echo "and remove any remaining slicer-tray entry manually if present."
}

main "$@"
