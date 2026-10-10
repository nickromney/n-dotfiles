#!/usr/bin/env bash
# Removes slicer-mac installation artifacts.
# Defaults to dry-run mode; pass --execute to actually remove.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=true
EXTRA_RUNTIME_DIRS=()

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: slicer-mac/remove-slicer-mac.sh [options]

Remove slicer-mac launch agents, bundles, CLI artifacts, caches, and crash files.
This script defaults to dry-run mode. Run as your login user, without sudo.
VM disks in removed bundles are deleted permanently. Credentials in ~/.slicer
are retained. Additional runtime directories must be specified explicitly.

Options:
  -d, --dry-run  Preview removals without deleting anything
      --execute  Remove slicer artifacts for real
      --runtime-dir DIR  Also remove runtime state and ALL top-level .img disks
                         in DIR (repeatable; directory itself is preserved)
      --no-input Non-interactive mode; --execute is explicit deletion consent
  -h, --help     Show this help message

Examples:
  slicer-mac/remove-slicer-mac.sh
  slicer-mac/remove-slicer-mac.sh --execute
  slicer-mac/remove-slicer-mac.sh --dry-run --runtime-dir /path/to/slicer-runtime
  slicer-mac/remove-slicer-mac.sh --execute --no-input --runtime-dir /path/to/slicer-runtime
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
      --runtime-dir)
        if [[ $# -lt 2 || -z "$2" || "$2" == -* || ! -d "$2" ]]; then
          echo "--runtime-dir requires an existing directory" >&2
          exit 1
        fi
        runtime_dir="$(cd "$2" && pwd -P)"
        if [[ "$runtime_dir" == / || "$runtime_dir" == "$(cd "$HOME" && pwd -P)" ]]; then
          echo "Refusing runtime directory: $runtime_dir (use a dedicated Slicer directory)" >&2
          exit 1
        fi
        EXTRA_RUNTIME_DIRS+=("$runtime_dir")
        shift 2
        ;;
      --no-input)
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

  if [[ "$(id -u)" -eq 0 ]]; then
    echo "Please do not run this script with sudo: Slicer uses per-user launchd services." >&2
    echo "Run without sudo: ./remove-slicer-mac.sh --execute" >&2
    exit 1
  fi

  # pgrep exit 1 means no matches; higher statuses mean inspection failed.
  process_status=0
  pgrep -u "$(id -u)" -x slicer-mac >/dev/null || process_status=$?
  if [[ "$process_status" -gt 1 ]]; then
    echo "Cannot inspect Slicer processes; refusing cleanup. Run from a normal terminal." >&2
    exit 1
  fi

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
    "sbox*.img"
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
    pgrep -u "$(id -u)" -x "$name" &>/dev/null && found_running_procs+=("$name") || true
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

  # Include the Stow package's nested directory as well as accidental state
  # beside this helper. Never recurse through config symlinks or shared folders.
  runtime_roots=("$SCRIPT_DIR" "$SCRIPT_DIR/slicer-mac")
  runtime_roots+=("${EXTRA_RUNTIME_DIRS[@]+"${EXTRA_RUNTIME_DIRS[@]}"}")
  for runtime_root in "${runtime_roots[@]}"; do
    [[ -d "$runtime_root" ]] || continue
    for name in "${RUNTIME_DIRS[@]}"; do
      path="$runtime_root/$name"
      [[ -e "$path" || -L "$path" ]] && found_runtime_wrong+=("$path") || true
    done
    runtime_globs=("${RUNTIME_GLOBS[@]}")
    for extra in "${EXTRA_RUNTIME_DIRS[@]+"${EXTRA_RUNTIME_DIRS[@]}"}"; do
      if [[ "$runtime_root" == "$extra" ]]; then
        runtime_globs+=("*.img")
        break
      fi
    done
    for glob in "${runtime_globs[@]}"; do
      for path in "$runtime_root"/$glob; do
        [[ -f "$path" || -L "$path" ]] && found_runtime_wrong+=("$path") || true
      done
    done
  done

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
    echo "  [runtime]  $path"
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
    pkill -u "$(id -u)" -x "$name" || true
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

  for name in "${KILL_PROCS[@]}"; do
    for ((attempt=0; attempt<10; attempt++)); do
      pgrep -u "$(id -u)" -x "$name" &>/dev/null || break
      sleep 1
    done
    if pgrep -u "$(id -u)" -x "$name" &>/dev/null; then
      echo "Refusing disk deletion: $name is still running. Stop it and retry." >&2
      exit 1
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
