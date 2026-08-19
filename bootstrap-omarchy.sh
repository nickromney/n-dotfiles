#!/usr/bin/env bash
# Bootstrap script for a fresh Omarchy (Arch Linux) installation.
#
# Mirrors bootstrap.sh's macOS flow but without Homebrew: Arch/Omarchy skips
# the Brewfile layer entirely and uses pacman for system packages instead.
#   1. pacman   — git, stow, keyd, mise, zsh + zsh plugins (system packages)
#   2. stow     — symlink dotfiles into $HOME (stow.sh)
#   3. login shell — make the stowed zsh/.zshrc the interactive default
#   4. keyd     — Caps Lock as Hyper modifier (see omarchy/README.md)
#   5. hypr     — include this repo's hyper.conf in ~/.config/hypr/bindings.conf
#   6. mise install — CLI tools and runtimes (mise/.config/mise/config.toml)
#
# See omarchy/README.md for the full manual walkthrough and the parts this
# script deliberately leaves to you (1Password sign-in, git SSH signing,
# mail client choice).

set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_INSTALL_DIR="${OMARCHY_INSTALL_DIR:-$HOME/.local/share/omarchy}"
ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-/usr/share/zsh/plugins}"
SHELLS_FILE="${SHELLS_FILE:-/etc/shells}"
KEYD_LINK="${KEYD_LINK:-/etc/keyd/n-dotfiles.conf}"
LOCALE_LANG="${LOCALE_LANG:-en_GB.UTF-8}"
# glibc reports the generated locale as "en_GB.utf8"; macOS reports
# "en_GB.UTF-8". Match either spelling rather than assuming one.
LOCALE_PRESENT_PATTERN="${LOCALE_PRESENT_PATTERN:-^en_GB\\.utf-?8$}"

DRY_RUN="${DRY_RUN:-false}"
NO_INPUT="${NO_INPUT:-false}"
SKIP_PACMAN=false
SKIP_LOCALE=false
SKIP_STOW=false
SKIP_SHELL=false
SKIP_KEYD=false
SKIP_HYPR=false
SKIP_MISE=false
STOW_PACKAGES="git zsh tmux mise codex claude agents omarchy"
STOW_PACKAGE_ARGS=()

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

Bootstrap a fresh Omarchy (Arch Linux) host: pacman base packages, stowed
dotfiles, Zsh as the login shell, keyd's Hyper-key remap, the Hyprland
hyper.conf include, and mise-managed CLI tools and runtimes.

Options:
  -d, --dry-run           Show what would happen without making changes
      --no-input          Disable prompts; pass --noconfirm to pacman
      --skip-pacman        Skip installing the pacman base packages
      --skip-locale        Skip generating the system locale
      --skip-stow          Skip stowing dotfiles
      --skip-shell         Keep the account's current login shell
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
  $0 --packages "git zsh tmux"
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
  echo "1. Log out and back in if the login shell changed; Ghostty will then start Zsh"
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

load_and_validate_stow_packages() {
  read -r -a STOW_PACKAGE_ARGS <<<"$STOW_PACKAGES"
  if [[ ${#STOW_PACKAGE_ARGS[@]} -eq 0 ]]; then
    error "--packages requires at least one package"
    exit 1
  fi

  local available pkg
  available="$("$BOOTSTRAP_DIR/stow.sh" --list)"
  for pkg in "${STOW_PACKAGE_ARGS[@]}"; do
    if ! grep -qxF "$pkg" <<<"$available"; then
      error "Unknown stow package: $pkg (use './stow.sh --list' to see packages)"
      exit 1
    fi
  done
}

run_locale_if_needed() {
  if [[ "$SKIP_LOCALE" == "true" ]]; then
    info "Skipping locale generation"
    return 0
  fi

  # zsh/.zshrc exports LANG, and on macOS that is enough because every locale
  # ships precompiled. glibc only has what locale-gen generated, so the same
  # export on a fresh Arch host names a locale that does not exist. Perl then
  # prints a 14-line warning to stderr on every invocation of any Perl-backed
  # tool, shasum included, which is easy to mistake for a broken command.
  if locale -a 2>/dev/null | grep -qiE "$LOCALE_PRESENT_PATTERN"; then
    info "Locale $LOCALE_LANG already generated"
    return 0
  fi

  info "Generating $LOCALE_LANG and setting it as the system locale..."
  run_cmd sudo sed -i "s/^#${LOCALE_LANG} UTF-8/${LOCALE_LANG} UTF-8/" /etc/locale.gen
  run_cmd sudo locale-gen
  run_cmd sudo localectl set-locale "LANG=${LOCALE_LANG}"
}

run_stow_if_needed() {
  if [[ "$SKIP_STOW" == "true" ]]; then
    info "Skipping stow"
    return 0
  fi

  info "Stowing dotfiles ($STOW_PACKAGES)..."
  local -a stow_args=()
  [[ "$DRY_RUN" == "true" ]] && stow_args+=("--dry-run")

  # A conflict in one package (e.g. real files already at ~/.config/nvim)
  # must not block unrelated later steps like keyd/hypr/mise — stow.sh
  # itself already continues past a failed package to the rest of the
  # list, so mirror that here rather than aborting the whole bootstrap.
  local stow_status=0
  if [[ ${#stow_args[@]} -gt 0 ]]; then
    "$BOOTSTRAP_DIR/stow.sh" "${stow_args[@]}" "${STOW_PACKAGE_ARGS[@]}" || stow_status=$?
  else
    "$BOOTSTRAP_DIR/stow.sh" "${STOW_PACKAGE_ARGS[@]}" || stow_status=$?
  fi
  if [[ "$stow_status" -ne 0 ]]; then
    error "Stow reported conflicts on one or more packages. Existing real files are in the way."
    error "Review them, then re-run './stow.sh' (or './stow.sh --adopt' to pull them into the repo — check 'git diff' afterwards)."
    error "Continuing with the rest of bootstrap; packages that failed to stow are simply not linked yet."
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

  local pkg binary any_missing=false
  for pkg in "${STOW_PACKAGE_ARGS[@]}"; do
    # Packages with no corresponding binary (meta/skill packages, or where
    # the binary name is not obvious) are intentionally skipped. A case keeps
    # this entrypoint compatible with macOS's stock Bash 3 as well as Arch.
    case "$pkg" in
      aerospace | aws | bash | bat | gh | ghostty | git | kitty | mise | nvim | prettier | starship | tmux | yazi | zsh)
        binary=$pkg
        ;;
      nushell)
        binary=nu
        ;;
      *)
        continue
        ;;
    esac
    if ! command_exists "$binary"; then
      info "  WARN $pkg: config stowed, but '$binary' is not on PATH"
      any_missing=true
    fi
  done

  if [[ "$any_missing" == "false" ]]; then
    info "  All stowed packages with a corresponding binary have it installed."
  fi
}

stow_package_requested() {
  local wanted="$1" pkg
  for pkg in "${STOW_PACKAGE_ARGS[@]}"; do
    [[ "$pkg" == "$wanted" ]] && return 0
  done
  return 1
}

# zsh/.zshrc sources these plugins directly by file path rather than via a
# binary, so check_stowed_binaries' PATH check can't see this dependency —
# check the actual plugin files zsh/.zshrc expects instead.
check_zsh_plugins() {
  stow_package_requested zsh || return 0

  local plugin plugin_file any_missing=false
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    plugin_file="$ZSH_PLUGIN_DIR/$plugin/$plugin.zsh"
    if [[ ! -f "$plugin_file" ]]; then
      info "  WARN $plugin: zsh is stowed, but $plugin_file is missing (pacman -S $plugin)"
      any_missing=true
    fi
  done

  if [[ "$any_missing" == "false" ]]; then
    info "  zsh-autosuggestions and zsh-syntax-highlighting are both present."
  fi
}

set_zsh_login_shell_if_needed() {
  if [[ "$SKIP_SHELL" == "true" ]]; then
    info "Skipping login shell setup"
    return 0
  fi

  if ! stow_package_requested zsh; then
    info "Skipping login shell setup because the zsh Stow package was not requested"
    return 0
  fi

  local zsh_path current_user passwd_entry current_shell active_zshrc expected_zshrc
  if ! zsh_path="$(command -v zsh)" || ! zsh_path="$(readlink -f "$zsh_path")"; then
    info "WARN zsh is not on PATH; cannot set it as the login shell"
    return 0
  fi

  if [[ ! -r "$SHELLS_FILE" ]] || ! grep -qxF "$zsh_path" "$SHELLS_FILE"; then
    info "WARN $zsh_path is not listed in $SHELLS_FILE; refusing to set it as the login shell"
    return 0
  fi

  expected_zshrc="$(readlink -f "$BOOTSTRAP_DIR/zsh/.zshrc")"
  active_zshrc="$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)"
  if [[ "$DRY_RUN" != "true" && "$active_zshrc" != "$expected_zshrc" ]]; then
    info "WARN $HOME/.zshrc is not linked to this repository; refusing to change the login shell"
    info "Resolve the zsh Stow conflict and re-run the bootstrap."
    return 0
  fi

  current_user="${USER:-$(id -un)}"
  passwd_entry="$(getent passwd "$current_user" 2>/dev/null || true)"
  if [[ -z "$passwd_entry" ]]; then
    info "WARN could not read the account record for $current_user; refusing to change the login shell"
    return 0
  fi
  current_shell="${passwd_entry##*:}"
  if [[ -e "$current_shell" ]]; then
    current_shell="$(readlink -f "$current_shell")"
  fi

  if [[ "$current_shell" == "$zsh_path" ]]; then
    info "Zsh is already the login shell for $current_user"
    return 0
  fi

  info "Setting Zsh as the login shell for $current_user..."
  run_cmd sudo chsh -s "$zsh_path" "$current_user"
  info "Log out and back in for Ghostty and other new terminals to use Zsh."
}

run_keyd_if_needed() {
  if [[ "$SKIP_KEYD" == "true" ]]; then
    info "Skipping keyd setup"
    return 0
  fi

  local keyd_source="$HOME/.config/keyd/default.conf"
  local keyd_link="$KEYD_LINK"

  if [[ ! -f "$keyd_source" ]] && ! { [[ "$DRY_RUN" == "true" ]] && stow_package_requested omarchy; }; then
    info "$keyd_source not found (stow the omarchy package first); skipping keyd setup"
    return 0
  fi

  if [[ -e "$keyd_link" || -L "$keyd_link" ]]; then
    if [[ "$(readlink -f "$keyd_link" 2>/dev/null || true)" != "$(readlink -f "$keyd_source" 2>/dev/null || true)" ]]; then
      info "WARN $keyd_link already exists but does not point to $keyd_source"
      info "Refusing to replace or activate an unexpected system keyd config."
      return 0
    fi
  fi

  info "Setting up keyd (Caps Lock as Hyper modifier)..."
  info "keyd's panic sequence is Backspace+Escape+Enter if a bad mapping traps the keyboard."
  info "Keep a second terminal or TTY open while this applies."

  run_cmd sudo install -d /etc/keyd

  if [[ -e "$keyd_link" || -L "$keyd_link" ]]; then
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
  local hyper_config="$HOME/.config/hypr/hyper.conf"
  local include_line="source = ~/.config/hypr/hyper.conf"

  if [[ ! -f "$bindings" ]]; then
    info "$bindings not found (Hyprland not set up yet?); skipping hyper.conf include"
    return 0
  fi

  if [[ ! -f "$hyper_config" ]] && ! { [[ "$DRY_RUN" == "true" ]] && stow_package_requested omarchy; }; then
    info "$hyper_config not found (stow the omarchy package first); skipping hyper.conf include"
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
    run_cmd hyprctl configerrors
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
      --skip-locale)
        SKIP_LOCALE=true
        shift
        ;;
      --skip-stow)
        SKIP_STOW=true
        shift
        ;;
      --skip-shell)
        SKIP_SHELL=true
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
  load_and_validate_stow_packages

  info "Starting n-dotfiles Omarchy bootstrap process..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Running in dry-run mode - no changes will be made"
  fi

  info "Creating Developer directory structure..."
  run_cmd mkdir -p "$HOME/Developer/personal"

  run_pacman_if_needed
  run_locale_if_needed
  run_stow_if_needed
  check_stowed_binaries
  check_zsh_plugins
  set_zsh_login_shell_if_needed
  run_keyd_if_needed
  run_hypr_include_if_needed
  run_mise_if_needed
  print_1password_status

  info "Bootstrap complete!"
  print_next_steps
}

main "$@"
