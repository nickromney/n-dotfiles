#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC1091
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_PROFILE="personal"
SETUP_PROFILE_DISPLAY="personal"
SETUP_PROFILE_DISPLAY_TITLE="Personal"
SETUP_TITLE="Personal Mac Setup"
SETUP_PROFILE_CONFIG="host/personal"
SETUP_PROFILE_CONFIG_PATH="_configs/host/personal.yaml"
SETUP_MACOS_CONFIG="_macos/personal.yaml"
SETUP_INCLUDE_MANUAL_CHECK=true
SETUP_INCLUDE_SSH=true

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Run the full personal Mac setup flow: bootstrap, packages, macOS settings, stow, VSCode, and SSH setup.

Options:
  -d, --dry-run             Show what would happen without making changes
      --no-input            Disable prompts and use safe non-interactive defaults
      --skip-bootstrap      Skip bootstrap even if brew, yq, or stow is missing
      --skip-packages       Skip shared/common and personal package installation
      --skip-profile-packages
                            Skip personal-only package installation
      --skip-manual-check   Skip manual application inventory checks
      --skip-macos          Skip applying macOS settings
      --skip-stow           Skip stow
      --skip-vscode         Skip VSCode extension installation
      --skip-ssh            Skip SSH setup from 1Password
  -h, --help                Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --dry-run --no-input --skip-vscode --skip-ssh
  $0 --skip-bootstrap --skip-manual-check
EOF

  exit "$exit_code"
}

print_next_steps() {
  info "Next steps:"
  echo "  1. Restart your terminal to load new shell configurations"
  echo "  2. Sign in to 1Password if not already done"
  echo "  3. Configure git with your personal email: git config --global user.email 'your-email@domain.com'"
  echo "  4. Verify SSH keys are working: ssh -T git@github.com"
  echo "  5. Sign into Mac App Store and re-run if any mas apps failed"
  echo "  6. Install any manually tracked apps shown above (Snagit, Camtasia, etc.)"
  echo
  info "You may also want to:"
  echo "  - Run 'make update' periodically to keep tools up to date"
  echo "  - Run 'make personal' to reinstall any missing packages"
}

# shellcheck source=scripts/setup-mac-lib.sh
source "$SETUP_SCRIPT_DIR/scripts/setup-mac-lib.sh"

setup_main "$@"
