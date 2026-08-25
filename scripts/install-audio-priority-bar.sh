#!/usr/bin/env bash
# Install the local AudioPriorityBar checkout.
#
# AudioPriorityBar is not currently distributed as a Homebrew cask, so this
# is the one macOS application installed outside Brewfile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${AUDIO_PRIORITY_BAR_SOURCE_DIR:-${HOME}/Developer/personal/AudioPriorityBar}"
BUILD_SCRIPT="${AUDIO_PRIORITY_BAR_BUILD_SCRIPT:-${SOURCE_DIR}/build.sh}"
APP_NAME="AudioPriorityBar.app"
APP_DIR="${AUDIO_PRIORITY_BAR_APP_DIR:-${HOME}/Applications}"
CONFIGURE_SCRIPT="${AUDIO_PRIORITY_BAR_CONFIGURE_SCRIPT:-${SCRIPT_DIR}/configure-audio-priority-bar.sh}"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.example.AudioPriorityBar.plist"
DRY_RUN=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Build the local AudioPriorityBar checkout and install it into a per-user
Applications directory. The universal binary requires macOS 13 or later.

Options:
  -a, --app-dir <path>  Install into this directory (default: ~/Applications)
  -d, --dry-run         Print the download and install plan without changing files
  -h, --help            Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --app-dir /Applications
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

warning() {
  echo "Warning: $*" >&2
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: $*"
    return 0
  fi

  "$@"
}

configure_preferences() {
  local -a configure_args=()
  [[ "$DRY_RUN" == "true" ]] && configure_args+=("--dry-run")
  "$CONFIGURE_SCRIPT" "${configure_args[@]}"
}

main() {
  local app_path app_stage source_app

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a | --app-dir)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          APP_DIR="$2"
          shift 2
        else
          error "--app-dir requires a path"
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

  if [[ "$DRY_RUN" != "true" && "$(uname -s)" != "Darwin" ]]; then
    error "AudioPriorityBar can only be installed on macOS"
    exit 1
  fi

  app_path="${APP_DIR}/${APP_NAME}"

  if [[ ! -d "$SOURCE_DIR" ]]; then
    warning "AudioPriorityBar source checkout not found: $SOURCE_DIR"
    echo "Skipping AudioPriorityBar build/install; clone the checkout there or set AUDIO_PRIORITY_BAR_SOURCE_DIR to enable it."
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would build ${SOURCE_DIR}"
    echo "[dry-run] Would install ${APP_NAME} to ${app_path}"
    echo "[dry-run] Would register ${LAUNCH_AGENT}"
    configure_preferences
    return 0
  fi

  if ! command -v ditto >/dev/null 2>&1; then
    error "Required command not found: ditto"
    exit 1
  fi

  app_stage="${APP_DIR}/.${APP_NAME}.new"

  if [[ ! -x "$BUILD_SCRIPT" ]]; then
    warning "AudioPriorityBar build script not found: $BUILD_SCRIPT"
    echo "Skipping AudioPriorityBar build/install; the source checkout is present but not buildable."
    return 0
  fi
  "$BUILD_SCRIPT"
  source_app="${SOURCE_DIR}/dist/${APP_NAME}"
  if [[ ! -d "$source_app" ]]; then
    error "Release archive did not contain ${APP_NAME}"
    exit 1
  fi

  mkdir -p "$APP_DIR"
  rm -rf "$app_stage"
  ditto "$source_app" "$app_stage"
  rm -rf "$app_path"
  mv "$app_stage" "$app_path"

  mkdir -p "${HOME}/Library/LaunchAgents"
  cat >"$LAUNCH_AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.AudioPriorityBar</string>
  <key>ProgramArguments</key>
  <array><string>${app_path}/Contents/MacOS/AudioPriorityBar</string></array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
  rm -f "${APP_DIR}/.AudioPriorityBar.release"

  echo "Installed local AudioPriorityBar from ${SOURCE_DIR} at ${app_path}"
  echo "Registered launch agent at ${LAUNCH_AGENT}"
  configure_preferences
  echo "Launch it once with: open -a '${app_path}'"
}

main "$@"
