#!/usr/bin/env bash
# Bootstrap script for a fresh macOS installation.
#
# The whole setup is three declarative layers:
#   1. brew bundle   — casks, fonts, Mac App Store apps, mac formulae (Brewfile)
#   2. stow          — symlink dotfiles into $HOME (stow.sh)
#   3. mise install  — CLI tools and runtimes (mise/.config/mise/config.toml)
#
# AI CLIs (claude, codex, opencode, copilot) are managed by their own
# native installers, not by brew or mise. See README.md.

set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
INSTALL_1PASSWORD=false
SKIP_1PASSWORD=false
SKIP_BREWFILE=false
SKIP_STOW=false
SKIP_MISE=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Bootstrap a fresh macOS host: Homebrew, Brewfile packages, stowed
dotfiles, and mise-managed CLI tools and runtimes.

Options:
  -d, --dry-run           Show what would happen without making changes
      --no-input          Disable prompts and use safe non-interactive defaults
      --install-1password Install 1Password without prompting
      --skip-1password    Skip 1Password installation
      --skip-brewfile     Skip applying ./Brewfile even if it exists
      --skip-stow         Skip stowing dotfiles
      --skip-mise         Skip running mise install
  -h, --help              Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --dry-run --no-input --skip-1password
  $0 --install-1password
  $0 --skip-brewfile --skip-mise
EOF

  exit "$exit_code"
}

info() {
  echo "$*"
}

error() {
  echo "Error: $*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_no_input() {
  [[ "$NO_INPUT" == "true" || -n "${NON_INTERACTIVE:-}" ]]
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: $*"
    return 0
  fi

  "$@"
}

print_next_steps() {
  echo
  echo "Next steps:"
  echo "1. Restart your terminal to load new shell configurations"
  echo "2. Run: make configure           # Apply macOS settings"
  echo "3. Run: ./setup-ssh-from-1password.sh   # If using 1Password for SSH"
  echo "4. Install AI CLIs via their native installers (see README.md)"
  echo
  echo "Keep things up to date with: make update"
}

ensure_macos() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This bootstrap script is designed for macOS only"
    error "On Linux: brew bundle --file Brewfile.posix && ./stow.sh && mise install"
    exit 1
  fi
}

ensure_brew_on_path() {
  if command_exists brew; then
    return 0
  fi

  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_homebrew_if_needed() {
  if command_exists brew; then
    info "Homebrew already installed"
    return 0
  fi

  info "Installing Homebrew..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "[dry-run] Would evaluate brew shellenv from /opt/homebrew/bin/brew or /usr/local/bin/brew if present."
    return 0
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_brew_on_path
}

run_brewfile_if_needed() {
  if [[ "$SKIP_BREWFILE" == "true" ]]; then
    info "Skipping Brewfile installation"
    # stow and mise are normally provided by the Brewfile
    run_cmd brew install stow mise
    return 0
  fi

  if [[ ! -f "$BOOTSTRAP_DIR/Brewfile" ]]; then
    error "No Brewfile found at $BOOTSTRAP_DIR/Brewfile"
    exit 1
  fi

  info "Installing Brewfile packages..."
  run_cmd brew bundle --file "$BOOTSTRAP_DIR/Brewfile"
}

run_stow_if_needed() {
  if [[ "$SKIP_STOW" == "true" ]]; then
    info "Skipping stow"
    return 0
  fi

  info "Stowing dotfiles..."
  local -a stow_args=()
  [[ "$DRY_RUN" == "true" ]] && stow_args+=("--dry-run")

  if ! "$BOOTSTRAP_DIR/stow.sh" "${stow_args[@]}"; then
    error "Stow reported conflicts. Existing real files are in the way."
    error "Review them, then re-run './stow.sh' (or './stow.sh --adopt' to pull them into the repo — check 'git diff' afterwards)."
    exit 1
  fi
}

run_mise_if_needed() {
  if [[ "$SKIP_MISE" == "true" ]]; then
    info "Skipping tools and runtimes via mise"
    return 0
  fi

  info "Installing CLI tools and runtimes via mise..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: mise install"
    return 0
  fi

  mise install
}

should_install_1password() {
  if [[ "$SKIP_1PASSWORD" == "true" ]]; then
    info "Skipping 1Password installation"
    return 1
  fi

  if [[ "$INSTALL_1PASSWORD" == "true" ]]; then
    return 0
  fi

  if is_no_input; then
    info "Skipping 1Password installation (non-interactive mode)."
    return 1
  fi

  read -r -p "Do you use 1Password for SSH keys? (y/n) " reply
  echo
  [[ "$reply" =~ ^[Yy]$ ]]
}

install_1password_if_requested() {
  if ! should_install_1password; then
    return 0
  fi

  info "Installing 1Password..."
  run_cmd brew install --cask 1password
  run_cmd brew install --cask 1password-cli
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
      --install-1password)
        INSTALL_1PASSWORD=true
        shift
        ;;
      --skip-1password)
        SKIP_1PASSWORD=true
        shift
        ;;
      --skip-brewfile)
        SKIP_BREWFILE=true
        shift
        ;;
      --skip-stow)
        SKIP_STOW=true
        shift
        ;;
      --skip-mise)
        SKIP_MISE=true
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

  if [[ "$INSTALL_1PASSWORD" == "true" && "$SKIP_1PASSWORD" == "true" ]]; then
    error "--install-1password and --skip-1password cannot be used together"
    usage 1
  fi
}

main() {
  parse_args "$@"
  ensure_macos

  info "Starting n-dotfiles bootstrap process..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Running in dry-run mode - no changes will be made"
  fi

  info "Creating Developer directory structure..."
  run_cmd mkdir -p "$HOME/Developer/personal"

  install_homebrew_if_needed
  ensure_brew_on_path
  run_brewfile_if_needed
  run_stow_if_needed
  run_mise_if_needed
  install_1password_if_requested

  info "Bootstrap complete!"
  print_next_steps
}

main "$@"
