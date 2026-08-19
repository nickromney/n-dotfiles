#!/usr/bin/env bash
# Install the pinned universal release of Tobi's AudioPriorityBar.
#
# AudioPriorityBar is not currently distributed as a Homebrew cask, so this
# is the one macOS application installed outside Brewfile. The release URL
# and SHA-256 are intentionally pinned; update both when adopting a release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="v1.2.1"
ARCHIVE="AudioPriorityBar.zip"
ARCHIVE_SHA256="f29f23d8cfcb90765aa5716983254d8aa6ac3c725de87b3aed8614eef0873bc0"
RELEASE_URL="https://github.com/tobi/AudioPriorityBar/releases/download/${RELEASE}/${ARCHIVE}"
APP_NAME="AudioPriorityBar.app"
APP_DIR="${AUDIO_PRIORITY_BAR_APP_DIR:-${HOME}/Applications}"
CONFIGURE_SCRIPT="${AUDIO_PRIORITY_BAR_CONFIGURE_SCRIPT:-${SCRIPT_DIR}/configure-audio-priority-bar.sh}"
DRY_RUN=false
INSTALL_TEMP_DIR=""

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Install Tobi's AudioPriorityBar ${RELEASE} release into a per-user
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
  local app_path marker_path marker_value archive extracted app_stage source_app

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
  marker_path="${APP_DIR}/.AudioPriorityBar.release"
  marker_value="${RELEASE} ${ARCHIVE_SHA256}"

  if [[ -d "$app_path" && -f "$marker_path" ]] && grep -Fqx -- "$marker_value" "$marker_path"; then
    echo "AudioPriorityBar ${RELEASE} is already installed at ${app_path}"
    configure_preferences
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would download ${RELEASE_URL}"
    echo "[dry-run] Would verify SHA-256: ${ARCHIVE_SHA256}"
    echo "[dry-run] Would install ${APP_NAME} to ${app_path}"
    configure_preferences
    return 0
  fi

  for command in curl ditto grep shasum; do
    if ! command -v "$command" >/dev/null 2>&1; then
      error "Required command not found: $command"
      exit 1
    fi
  done

  INSTALL_TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$INSTALL_TEMP_DIR"' EXIT
  archive="${INSTALL_TEMP_DIR}/${ARCHIVE}"
  extracted="${INSTALL_TEMP_DIR}/extracted"
  app_stage="${APP_DIR}/.${APP_NAME}.new"

  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$RELEASE_URL" --output "$archive"
  printf '%s  %s\n' "$ARCHIVE_SHA256" "$archive" | shasum -a 256 -c --status
  mkdir -p "$extracted"
  ditto -x -k "$archive" "$extracted"

  source_app="${extracted}/${APP_NAME}"
  if [[ ! -d "$source_app" ]]; then
    error "Release archive did not contain ${APP_NAME}"
    exit 1
  fi

  mkdir -p "$APP_DIR"
  rm -rf "$app_stage"
  ditto "$source_app" "$app_stage"
  rm -rf "$app_path"
  mv "$app_stage" "$app_path"
  printf '%s\n' "$marker_value" >"$marker_path"

  echo "Installed AudioPriorityBar ${RELEASE} at ${app_path}"
  configure_preferences
  echo "Launch it once with: open -a '${app_path}'"
}

main "$@"
