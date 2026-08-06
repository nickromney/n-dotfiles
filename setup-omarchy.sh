#!/usr/bin/env bash
# Set up the n-dotfiles layers that belong on an Omarchy/Arch host.
#
# Omarchy owns the desktop and system defaults. This script only installs the
# small Arch prerequisites needed by this repository, stows selected personal
# layers, installs mise-managed tools, and adds the Hyper bindings include.

set -euo pipefail

SETUP_OMARCHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
WITH_GIT="${WITH_GIT:-false}"
SKIP_KEYD="${SKIP_KEYD:-false}"

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Set up n-dotfiles on an Omarchy/Arch Linux host without replacing Omarchy's
managed desktop configuration.

Options:
  -d, --dry-run   Show what would happen without changing the system
      --no-input  Pass non-interactive options to pacman
      --with-git   Also stow the git package (review its macOS signer setting)
      --skip-keyd  Skip the keyd link, validation, and service setup
  -h, --help      Show this help message

Examples:
  $0 --dry-run
  $0
  $0 --no-input --skip-keyd
  $0 --with-git

The default stow set is: zsh nvim tmux mise codex claude agents omarchy
Git is opt-in because the tracked git config references the macOS 1Password
SSH signer path.
EOF

  exit "$exit_code"
}

info() {
  echo "$*"
}

error() {
  echo "Error: $*" >&2
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[dry-run] Would execute:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
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
      --with-git)
        WITH_GIT=true
        shift
        ;;
      --skip-keyd)
        SKIP_KEYD=true
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

require_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    error "This script is for Omarchy/Arch Linux only"
    exit 1
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    error "pacman not found; this script expects an Arch-based host"
    exit 1
  fi
}

install_prerequisites() {
  local -a pacman_args=(--needed)
  [[ "$NO_INPUT" == "true" ]] && pacman_args+=(--noconfirm)

  info "Installing Arch prerequisites: git stow keyd mise"
  run_cmd sudo pacman -S "${pacman_args[@]}" git stow keyd mise
}

stow_personal_layers() {
  local -a packages=(zsh nvim tmux mise codex claude agents omarchy)
  local -a stow_args=("$SETUP_OMARCHY_DIR/stow.sh")

  if [[ "$WITH_GIT" == "true" ]]; then
    packages=(git "${packages[@]}")
    info "Including git; verify the Linux SSH signing program before committing"
  fi

  [[ "$DRY_RUN" == "true" ]] && stow_args+=(--dry-run)
  stow_args+=("${packages[@]}")

  info "Stowing personal layers: ${packages[*]}"
  run_cmd "${stow_args[@]}"
}

install_mise_tools() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Installing mise-managed tools"
    run_cmd mise install
    return 0
  fi

  if ! command -v mise >/dev/null 2>&1; then
    error "mise is still unavailable after installing Arch prerequisites"
    exit 1
  fi

  info "Installing mise-managed tools"
  mise install
}

ensure_hyprland_include() {
  local bindings_file="$HOME/.config/hypr/bindings.conf"
  local include_line='source = ~/.config/hypr/hyper.conf'

  if [[ -f "$bindings_file" ]] && grep -Fqx "$include_line" "$bindings_file"; then
    info "Hyprland Hyper bindings include already present"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would add the Hyper bindings include to $bindings_file"
    return 0
  fi

  mkdir -p "$(dirname "$bindings_file")"
  if [[ -s "$bindings_file" ]]; then
    printf '\n' >>"$bindings_file"
  fi
  printf '%s\n' "$include_line" >>"$bindings_file"
  info "Added the Hyper bindings include to $bindings_file"
}

ensure_keyd() {
  local source_file="$HOME/.config/keyd/default.conf"
  local target_file="/etc/keyd/n-dotfiles.conf"

  if [[ "$SKIP_KEYD" == "true" ]]; then
    info "Skipping keyd setup"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would link $target_file to $source_file"
    run_cmd sudo keyd check "$target_file"
    run_cmd sudo systemctl enable --now keyd
    run_cmd sudo keyd reload
    return 0
  fi

  if [[ ! -f "$source_file" ]]; then
    error "Stowed keyd config not found at $source_file"
    exit 1
  fi

  if [[ -e "$target_file" || -L "$target_file" ]]; then
    if [[ ! -L "$target_file" || "$(readlink "$target_file")" != "$source_file" ]]; then
      error "$target_file already exists and is not the n-dotfiles symlink"
      error "Review it manually; refusing to overwrite Omarchy or another keyd config"
      exit 1
    fi
    info "keyd config link already present"
  else
    sudo install -d /etc/keyd
    sudo ln -s "$source_file" "$target_file"
    info "Linked keyd config to $target_file"
  fi

  sudo keyd check "$target_file"
  sudo systemctl enable --now keyd
  sudo keyd reload
}

print_next_steps() {
  echo
  echo "Next steps:"
  echo "  1. Restart the terminal so the stowed shell and mise config are active"
  echo "  2. Run: mise ls"
  echo "  3. Authenticate GitHub when ready: gh auth login"
  if [[ "$WITH_GIT" != "true" ]]; then
    echo "  4. Stow git separately after configuring a Linux SSH signer: ./stow.sh git"
  fi
}

main() {
  parse_args "$@"
  require_linux
  cd "$SETUP_OMARCHY_DIR"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Running in dry-run mode"
  fi

  install_prerequisites
  stow_personal_layers
  install_mise_tools
  ensure_hyprland_include
  ensure_keyd

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Omarchy setup dry run complete"
  else
    info "Omarchy setup complete"
    print_next_steps
  fi
}

main "$@"
