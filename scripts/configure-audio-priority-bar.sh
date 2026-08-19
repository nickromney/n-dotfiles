#!/usr/bin/env bash
# Merge the repo-managed AudioPriorityBar preferences into macOS UserDefaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="com.example.AudioPriorityBar"
STOWED_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/audio-priority-bar/preferences.plist"
REPO_CONFIG="${SCRIPT_DIR}/../audio-priority-bar/.config/audio-priority-bar/preferences.plist"
CONFIG_PATH=""
CONFIG_TEMP_DIR=""
DRY_RUN=false

MANAGED_KEYS=(
  currentMode
  customMode
  inputPriorities
  speakerPriorities
  headphonePriorities
  deviceCategories
  hiddenMics
  hiddenSpeakers
  hiddenHeadphones
  neverUseDevices
)

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Merge stable AudioPriorityBar preferences into ${DOMAIN} while preserving its
volatile knownDevices cache.

Options:
  -c, --config <path>  Read this plist instead of the stowed/repo default
  -d, --dry-run        Validate and print the merge plan without changing defaults
  -h, --help           Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --config ~/.config/audio-priority-bar/preferences.plist
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

resolve_config() {
  if [[ -n "$CONFIG_PATH" ]]; then
    return
  fi
  if [[ -f "$STOWED_CONFIG" ]]; then
    CONFIG_PATH=$STOWED_CONFIG
  else
    CONFIG_PATH=$REPO_CONFIG
  fi
}

main() {
  local working_plist key value value_type value_format managed_count=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c | --config)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          CONFIG_PATH=$2
          shift 2
        else
          error "--config requires a path"
          usage 1
        fi
        ;;
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

  resolve_config
  if [[ ! -f "$CONFIG_PATH" ]]; then
    error "AudioPriorityBar preferences not found: $CONFIG_PATH"
    return 1
  fi
  plutil -lint "$CONFIG_PATH" >/dev/null

  for key in "${MANAGED_KEYS[@]}"; do
    if plutil -type "$key" "$CONFIG_PATH" >/dev/null 2>&1; then
      managed_count=$((managed_count + 1))
    fi
  done
  if [[ "$managed_count" -eq 0 ]]; then
    error "No managed AudioPriorityBar keys found in $CONFIG_PATH"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would merge ${managed_count} managed preferences from ${CONFIG_PATH} into ${DOMAIN}"
    echo "[dry-run] Would preserve the app-managed knownDevices cache"
    return 0
  fi
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error "AudioPriorityBar preferences can only be applied on macOS"
    return 1
  fi

  CONFIG_TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$CONFIG_TEMP_DIR"' EXIT
  working_plist="$CONFIG_TEMP_DIR/preferences.plist"
  if ! defaults export "$DOMAIN" "$working_plist" >/dev/null 2>&1; then
    plutil -create xml1 "$working_plist"
  fi

  for key in "${MANAGED_KEYS[@]}"; do
    if ! value_type=$(plutil -type "$key" "$CONFIG_PATH" 2>/dev/null); then
      continue
    fi
    case "$value_type" in
      array | dictionary)
        value=$(plutil -extract "$key" json -o - "$CONFIG_PATH")
        value_format=json
        ;;
      *)
        value=$(plutil -extract "$key" raw -o - "$CONFIG_PATH")
        value_format=$value_type
        ;;
    esac
    if plutil -type "$key" "$working_plist" >/dev/null 2>&1; then
      plutil -replace "$key" "-$value_format" "$value" "$working_plist"
    else
      plutil -insert "$key" "-$value_format" "$value" "$working_plist"
    fi
  done

  defaults import "$DOMAIN" "$working_plist" >/dev/null
  echo "Applied ${managed_count} AudioPriorityBar preferences from ${CONFIG_PATH}"
}

main "$@"
