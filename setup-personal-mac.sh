#!/usr/bin/env bash
# Full personal Mac setup: bootstrap (brew bundle + stow + mise),
# macOS settings, and SSH keys from 1Password.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_MACOS_CONFIG="_macos/personal.yaml"

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-false}"
SKIP_MACOS="${SKIP_MACOS:-false}"
SKIP_SSH="${SKIP_SSH:-false}"

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Run the full personal Mac setup flow: bootstrap (Homebrew, Brewfile,
stow, mise), macOS settings, and SSH setup from 1Password.

Options:
  -d, --dry-run         Show what would happen without making changes
      --no-input        Disable prompts and use safe non-interactive defaults
      --skip-bootstrap  Skip bootstrap (brew bundle, stow, mise)
      --skip-macos      Skip applying macOS settings
      --skip-ssh        Skip SSH setup from 1Password
  -h, --help            Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --dry-run --no-input --skip-ssh
  $0 --skip-bootstrap
EOF

  exit "$exit_code"
}

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

error() {
  echo -e "${RED}✗${NC} $*" >&2
}

section() {
  echo
  echo -e "${GREEN}=== $* ===${NC}"
  echo
}

setup_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

setup_with_non_interactive_env() {
  if [[ "$NO_INPUT" == "true" ]]; then
    env NON_INTERACTIVE=1 NO_INPUT=true "$@"
  else
    "$@"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d | --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-input)
        NO_INPUT=true
        shift
        ;;
      --skip-bootstrap)
        SKIP_BOOTSTRAP=true
        shift
        ;;
      --skip-macos)
        SKIP_MACOS=true
        shift
        ;;
      --skip-ssh)
        SKIP_SSH=true
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
}

require_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    error "This script is for macOS only"
    exit 1
  fi
}

run_bootstrap() {
  local -a args=()

  if [[ "$SKIP_BOOTSTRAP" == "true" ]]; then
    info "Skipping bootstrap"
    return 0
  fi

  section "Bootstrap (Homebrew + Brewfile + stow + mise)"
  if [[ "$DRY_RUN" == "true" ]]; then
    args+=(--dry-run)
  fi
  if [[ "$NO_INPUT" == "true" ]]; then
    args+=(--no-input)
  fi
  if ! setup_with_non_interactive_env ./bootstrap.sh "${args[@]}"; then
    error "Bootstrap failed"
    exit 1
  fi
  success "Bootstrap completed"
}

run_macos() {
  local -a args=()

  if [[ "$SKIP_MACOS" == "true" ]]; then
    info "Skipping macOS configuration"
    return 0
  fi

  section "Applying macOS system settings"
  if [[ ! -f "$SETUP_MACOS_CONFIG" ]]; then
    warning "No macOS configuration found at $SETUP_MACOS_CONFIG"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    args+=(--dry-run)
  fi
  if [[ "$NO_INPUT" == "true" ]]; then
    args+=(--no-input)
  fi
  args+=("personal.yaml")
  if ! setup_with_non_interactive_env ./_macos/macos.sh "${args[@]}"; then
    error "macOS configuration failed"
    exit 1
  fi
  success "macOS settings applied"
}

run_ssh() {
  local -a args=()

  if [[ "$SKIP_SSH" == "true" ]]; then
    info "Skipping SSH setup"
    return 0
  fi

  section "SSH Configuration"
  if [[ -f "./setup-ssh-from-1password.sh" ]] && setup_command_exists op; then
    info "Setting up SSH configuration and keys from 1Password..."
    args=(--profile personal)
    if [[ "$DRY_RUN" == "true" ]]; then
      args+=(--dry-run)
    fi
    if [[ "$NO_INPUT" == "true" ]]; then
      args+=(--no-input)
    fi
    if setup_with_non_interactive_env ./setup-ssh-from-1password.sh "${args[@]}"; then
      success "SSH configuration completed"
    else
      warning "SSH setup encountered issues - you may need to run ./setup-ssh-from-1password.sh manually"
    fi
  else
    warning "1Password CLI not found or SSH setup script missing"
    echo "  To set up SSH later, run: ./setup-ssh-from-1password.sh --profile personal"
  fi
}

print_next_steps() {
  info "Next steps:"
  echo "  1. Restart your terminal to load new shell configurations"
  echo "  2. Sign in to 1Password if not already done"
  echo "  3. Verify SSH keys are working: ssh -T git@github.com"
  echo "  4. Sign into Mac App Store and re-run 'brew bundle' if any mas apps failed"
  echo "  5. Install AI CLIs via their native installers (see README.md)"
  echo
  info "You may also want to:"
  echo "  - Run 'make update' periodically to keep tools up to date"
}

main() {
  parse_args "$@"
  require_macos

  if [[ -n "${NON_INTERACTIVE:-}" ]]; then
    NO_INPUT=true
  fi

  cd "$SETUP_SCRIPT_DIR" || exit 1
  section "Personal Mac Setup"

  run_bootstrap
  run_macos
  run_ssh

  section "Setup Complete!"
  if [[ "$DRY_RUN" == "true" ]]; then
    success "Personal Mac setup dry run completed"
  else
    success "Personal Mac setup completed successfully"
  fi
  echo
  print_next_steps
}

main "$@"
