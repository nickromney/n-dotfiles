#!/usr/bin/env bash
# Bootstrap script for fresh macOS installation.
# This handles the chicken-and-egg problem of needing tools to install tools.

set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
INSTALL_1PASSWORD=false
SKIP_1PASSWORD=false
SKIP_BREWFILE=false
SKIP_MISE=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Bootstrap a fresh macOS host with Homebrew, required tooling, optional Brewfile packages, and mise runtimes.

Options:
  -d, --dry-run           Show what would happen without making changes
      --no-input          Disable prompts and use safe non-interactive defaults
      --install-1password Install 1Password without prompting
      --skip-1password    Skip 1Password installation
      --skip-brewfile     Skip applying ./Brewfile even if it exists
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
  echo "1. Run: make install              # Preferred install (Brewfile + mise + legacy bridge)"
  echo "2. Run: make personal stow        # Stow configurations"
  echo "3. Run: make personal configure   # Apply macOS settings"
  echo "4. Run: make vscode install       # If using VSCode"
  echo "5. Run: make neovim install       # If using Neovim"
  echo
  echo "Legacy fallback (deprecated):"
  echo "  ./install.sh -d"
  echo "  ./install.sh"
}

ensure_macos() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This bootstrap script is designed for macOS only"
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

install_essential_tools() {
  info "Installing essential tools..."
  run_cmd brew install yq
  run_cmd brew install stow
  run_cmd brew install mise
}

run_brewfile_if_needed() {
  if [[ "$SKIP_BREWFILE" == "true" ]]; then
    info "Skipping Brewfile installation"
    return 0
  fi

  if [[ ! -f "./Brewfile" ]]; then
    info "No Brewfile found, skipping Brewfile installation"
    return 0
  fi

  info "Installing Brewfile packages (preferred path)..."
  run_cmd brew bundle --file ./Brewfile --no-lock
}

run_mise_if_needed() {
  if [[ "$SKIP_MISE" == "true" ]]; then
    info "Skipping runtimes via mise"
    return 0
  fi

  info "Installing runtimes via mise..."
  run_cmd mise install
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
  install_essential_tools
  run_brewfile_if_needed
  run_mise_if_needed
  install_1password_if_requested

  info "Bootstrap complete!"
  print_next_steps
}

main "$@"
