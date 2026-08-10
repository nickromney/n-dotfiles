#!/usr/bin/env bash
# Bootstrap script for a fresh Omarchy (Arch Linux) installation.
#
# Mirrors bootstrap.sh's macOS flow but without Homebrew: Arch/Omarchy skips
# the Brewfile layer entirely and uses pacman for system packages instead.
#   1. pacman   — git, stow, keyd, mise, zsh + zsh plugins (system packages)
#   2. stow     — symlink dotfiles into $HOME (stow.sh)
#   3. keyd     — Caps Lock as Hyper modifier (see omarchy/README.md)
#   4. hypr     — include this repo's hyper.conf in ~/.config/hypr/bindings.conf
#   5. mise install — CLI tools and runtimes (mise/.config/mise/config.toml)
#
# See omarchy/README.md for the full manual walkthrough and the parts this
# script deliberately leaves to you (1Password sign-in, git SSH signing,
# mail client choice).

set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_INSTALL_DIR="${OMARCHY_INSTALL_DIR:-$HOME/.local/share/omarchy}"
ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-/usr/share/zsh/plugins}"

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
SKIP_PACMAN=false
SKIP_STOW=false
SKIP_KEYD=false
SKIP_HYPR=false
SKIP_MISE=false
STOW_PACKAGES="git zsh nvim tmux mise codex claude agents omarchy"

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Bootstrap a fresh Omarchy (Arch Linux) host: pacman base packages, stowed
dotfiles, keyd's Hyper-key remap, the Hyprland hyper.conf include, and
mise-managed CLI tools and runtimes.

Options:
  -d, --dry-run           Show what would happen without making changes
      --no-input          Disable prompts; pass --noconfirm to pacman
      --skip-pacman        Skip installing git/stow/keyd/mise via pacman
      --skip-stow          Skip stowing dotfiles
      --skip-keyd          Skip keyd symlink/enable/reload
      --skip-hypr          Skip adding the hyper.conf include to bindings.conf
      --skip-mise          Skip running mise install
      --packages "LIST"    Space-separated stow packages (default: "$STOW_PACKAGES")
  -h, --help              Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --dry-run --no-input
  $0 --skip-keyd --skip-hypr
  $0 --packages "git zsh nvim"
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
  echo "2. 1Password: sign in to the app, then Settings > Developer >"
  echo "   enable 'Integrate with 1Password CLI' and 'Use the SSH agent'"
  echo "3. Run: ./setup-ssh-from-1password.sh --dry-run"
  echo "4. Run: ./setup-gitconfig-from-1password.sh --dry-run"
  echo "5. Optional: make hooks   # install this repo's lefthook git hooks"
  echo
  echo "See omarchy/README.md for git signing, mail, and AI CLI setup."
}

ensure_omarchy() {
  if [[ "$OSTYPE" != linux* ]]; then
    error "This bootstrap script is designed for Arch/Omarchy (Linux) only"
    error "On macOS: ./bootstrap.sh"
    exit 1
  fi

  if [[ ! -d "$OMARCHY_INSTALL_DIR" ]]; then
    error "Omarchy install directory not found at $OMARCHY_INSTALL_DIR"
    error "This script targets Omarchy specifically. For generic Linux,"
    error "see README.md's Linux section (Homebrew on Linux + Brewfile.posix)."
    exit 1
  fi
}

run_pacman_if_needed() {
  if [[ "$SKIP_PACMAN" == "true" ]]; then
    info "Skipping pacman base packages"
    return 0
  fi

  info "Installing base packages via pacman (git, stow, keyd, mise, zsh, zsh-autosuggestions, zsh-syntax-highlighting)..."
  local -a pacman_args=(-S --needed)
  is_no_input && pacman_args+=(--noconfirm)
  run_cmd sudo pacman "${pacman_args[@]}" git stow keyd mise zsh zsh-autosuggestions zsh-syntax-highlighting
}

run_stow_if_needed() {
  if [[ "$SKIP_STOW" == "true" ]]; then
    info "Skipping stow"
    return 0
  fi

  info "Stowing dotfiles ($STOW_PACKAGES)..."
  local -a stow_args=()
  [[ "$DRY_RUN" == "true" ]] && stow_args+=("--dry-run")

  # shellcheck disable=SC2086 # STOW_PACKAGES is an intentionally unquoted word list
  if ! "$BOOTSTRAP_DIR/stow.sh" "${stow_args[@]}" $STOW_PACKAGES; then
    error "Stow reported conflicts. Existing real files are in the way."
    error "Review them, then re-run './stow.sh' (or './stow.sh --adopt' to pull them into the repo — check 'git diff' afterwards)."
    exit 1
  fi
}

# Stowing a package's config doesn't install the tool it configures — pacman
# and this package list evolve separately, so it's easy for one to drift
# ahead of the other (this is how the zsh gap above happened: zsh was in the
# default stow list for a long time before the pacman step actually
# installed the zsh binary). Catch that class of gap here instead of via a
# confusing later failure in an unrelated command.
check_stowed_binaries() {
  echo
  info "Checking that stowed packages have their tool installed..."

  # Packages with no corresponding binary (meta/skill packages, or where the
  # binary name doesn't match the package name in an obvious way) are
  # intentionally absent from this table and skipped.
  local -A package_binary=(
    [aerospace]=aerospace
    [aws]=aws
    [bash]=bash
    [bat]=bat
    [gh]=gh
    [ghostty]=ghostty
    [git]=git
    [kitty]=kitty
    [mise]=mise
    [nushell]=nu
    [nvim]=nvim
    [prettier]=prettier
    [starship]=starship
    [tmux]=tmux
    [yazi]=yazi
    [zsh]=zsh
  )

  local pkg binary any_missing=false
  for pkg in $STOW_PACKAGES; do
    binary="${package_binary[$pkg]:-}"
    [[ -z "$binary" ]] && continue
    if ! command_exists "$binary"; then
      info "  WARN $pkg: config stowed, but '$binary' is not on PATH"
      any_missing=true
    fi
  done

  if [[ "$any_missing" == "false" ]]; then
    info "  All stowed packages with a corresponding binary have it installed."
  fi
}

# zsh/.zshrc sources these plugins directly by file path rather than via a
# binary, so check_stowed_binaries' PATH check can't see this dependency —
# check the actual plugin files zsh/.zshrc expects instead.
check_zsh_plugins() {
  local zsh_requested=false pkg
  for pkg in $STOW_PACKAGES; do
    [[ "$pkg" == "zsh" ]] && zsh_requested=true
  done
  [[ "$zsh_requested" == "false" ]] && return 0

  local -A plugin_path=(
    [zsh-autosuggestions]="$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
    [zsh-syntax-highlighting]="$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  )

  local plugin plugin_file any_missing=false
  for plugin in "${!plugin_path[@]}"; do
    plugin_file="${plugin_path[$plugin]}"
    if [[ ! -f "$plugin_file" ]]; then
      info "  WARN $plugin: zsh is stowed, but $plugin_file is missing (pacman -S $plugin)"
      any_missing=true
    fi
  done

  if [[ "$any_missing" == "false" ]]; then
    info "  zsh-autosuggestions and zsh-syntax-highlighting are both present."
  fi
}

run_keyd_if_needed() {
  if [[ "$SKIP_KEYD" == "true" ]]; then
    info "Skipping keyd setup"
    return 0
  fi

  local keyd_source="$HOME/.config/keyd/default.conf"
  local keyd_link="/etc/keyd/n-dotfiles.conf"

  if [[ ! -f "$keyd_source" ]]; then
    info "$keyd_source not found (stow the omarchy package first); skipping keyd setup"
    return 0
  fi

  info "Setting up keyd (Caps Lock as Hyper modifier)..."
  info "keyd's panic sequence is Backspace+Escape+Enter if a bad mapping traps the keyboard."
  info "Keep a second terminal or TTY open while this applies."

  run_cmd sudo install -d /etc/keyd

  if [[ -e "$keyd_link" ]]; then
    info "$keyd_link already present; leaving it as-is"
  else
    run_cmd sudo ln -s "$keyd_source" "$keyd_link"
  fi

  run_cmd sudo keyd check "$keyd_link"
  run_cmd sudo systemctl enable --now keyd
  run_cmd sudo keyd reload
}

run_hypr_include_if_needed() {
  if [[ "$SKIP_HYPR" == "true" ]]; then
    info "Skipping Hyprland hyper.conf include"
    return 0
  fi

  local bindings="$HOME/.config/hypr/bindings.conf"
  local include_line="source = ~/.config/hypr/hyper.conf"

  if [[ ! -f "$bindings" ]]; then
    info "$bindings not found (Hyprland not set up yet?); skipping hyper.conf include"
    return 0
  fi

  if grep -qxF "$include_line" "$bindings" 2>/dev/null; then
    info "hyper.conf already included in $bindings"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would append to $bindings: $include_line"
    return 0
  fi

  echo "$include_line" >>"$bindings"
  info "Added hyper.conf include to $bindings"

  if command_exists hyprctl; then
    run_cmd hyprctl reload
  fi
}

run_mise_if_needed() {
  if [[ "$SKIP_MISE" == "true" ]]; then
    info "Skipping tools and runtimes via mise"
    return 0
  fi

  if ! command_exists mise; then
    info "mise not found on PATH; skipping mise install (re-run after pacman step)"
    return 0
  fi

  info "Installing CLI tools and runtimes via mise..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: mise install"
    return 0
  fi

  if ! mise install; then
    info "mise install reported failures for one or more tools; re-run 'mise install' to retry, or 'mise install <tool>' for a specific one."
  fi
}

print_1password_status() {
  echo
  info "Checking 1Password developer tools (CLI, SSH agent, SSH signing)..."
  "$BOOTSTRAP_DIR/scripts/check-1password-dev-tools.sh" || true
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
      --skip-pacman)
        SKIP_PACMAN=true
        shift
        ;;
      --skip-stow)
        SKIP_STOW=true
        shift
        ;;
      --skip-keyd)
        SKIP_KEYD=true
        shift
        ;;
      --skip-hypr)
        SKIP_HYPR=true
        shift
        ;;
      --skip-mise)
        SKIP_MISE=true
        shift
        ;;
      --packages)
        if [[ -n "${2:-}" ]]; then
          STOW_PACKAGES="$2"
          shift 2
        else
          error "--packages requires a value"
          usage 1
        fi
        ;;
      --packages=*)
        STOW_PACKAGES="${1#*=}"
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

main() {
  parse_args "$@"
  ensure_omarchy

  info "Starting n-dotfiles Omarchy bootstrap process..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Running in dry-run mode - no changes will be made"
  fi

  info "Creating Developer directory structure..."
  run_cmd mkdir -p "$HOME/Developer/personal"

  run_pacman_if_needed
  run_stow_if_needed
  check_stowed_binaries
  check_zsh_plugins
  run_keyd_if_needed
  run_hypr_include_if_needed
  run_mise_if_needed
  print_1password_status

  info "Bootstrap complete!"
  print_next_steps
}

main "$@"
