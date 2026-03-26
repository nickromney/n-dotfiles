#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC1091
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_PROFILE="work"
SETUP_PROFILE_DISPLAY="work"
SETUP_PROFILE_DISPLAY_TITLE="Work"
SETUP_TITLE="Work Mac Setup"
SETUP_PROFILE_CONFIG="host/work"
SETUP_PROFILE_CONFIG_PATH="_configs/host/work.yaml"
SETUP_MACOS_CONFIG="_macos/work.yaml"
SETUP_INCLUDE_MANUAL_CHECK=false
SETUP_INCLUDE_SSH=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Run the full work Mac setup flow: bootstrap, packages, macOS settings, stow, and VSCode.

Options:
  -d, --dry-run             Show what would happen without making changes
      --no-input            Disable prompts and use safe non-interactive defaults
      --skip-bootstrap      Skip bootstrap even if brew, yq, or stow is missing
      --skip-packages       Skip shared/common and work package installation
      --skip-profile-packages
                            Skip work-only package installation
      --skip-macos          Skip applying macOS settings
      --skip-stow           Skip stow
      --skip-vscode         Skip VSCode extension installation
  -h, --help                Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --dry-run --no-input --skip-vscode
  $0 --skip-bootstrap --skip-profile-packages
EOF

  exit "$exit_code"
}

print_next_steps() {
  info "Next steps:"
  echo "  1. Restart your terminal to load new shell configurations"
  echo "  2. Sign in to 1Password if not already done"
  echo "  3. Configure git with your work email: git config --global user.email 'your-work-email@company.com'"
  echo "  4. Set up SSH keys for GitHub/GitLab access"
  echo "  5. Install any company-specific tools or certificates"
  echo
  info "You may also want to:"
  echo "  - Create a work-specific macOS configuration at _macos/work.yaml"
  echo "  - Create a work-specific tools configuration at _configs/host/work.yaml"
  echo "  - Run 'make update' periodically to keep tools up to date"
}

# shellcheck source=scripts/setup-mac-lib.sh
source "$SETUP_SCRIPT_DIR/scripts/setup-mac-lib.sh"

setup_main "$@"
