#!/usr/bin/env bash
# Symlink dotfiles into $HOME with GNU Stow.
#
# This is the only entrypoint a stow-only machine (e.g. work) needs:
#   git clone <repo> && cd n-dotfiles && ./stow.sh

set -euo pipefail

STOW_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each directory is a GNU Stow package targeting $HOME.
STOW_DIRS=(
  agents
  aws
  bash
  bat
  claude
  codex
  gh
  ghostty
  git
  kitty
  mise
  nushell
  nvim
  prettier
  ssh
  starship
  tmux
  yazi
  zsh
)

# Keep host-specific app and desktop configuration off the other platform.
# In particular, a Mac sync must never touch Omarchy's Hyprland/keyd paths.
case "$(uname -s)" in
  Darwin) STOW_DIRS+=(aerospace audio-priority-bar) ;;
  Linux) STOW_DIRS+=(omarchy) ;;
esac

DRY_RUN=false
ADOPT=false
BACKUP_CONFLICTS=false
BACKUP_DIR=""
ACTIVE_BACKUP_ROOT=""
BACKED_UP_RELATIVE_PATHS=()
LIST_MODE=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options] [package ...]

Symlink dotfile packages into \$HOME using GNU Stow (restow mode).
With no package arguments, all packages are stowed.

Options:
  -d, --dry-run   Show what would change without making changes
  -a, --adopt     Adopt pre-existing files into the repo (review with git diff!)
      --backup-conflicts
                  Back up pre-existing targets, then stow the repo versions
      --backup-dir PATH
                  Backup destination (requires --backup-conflicts)
  -l, --list      List available stow packages
  -h, --help      Show this help message

Examples:
  $0
  $0 --dry-run
  $0 zsh git
  $0 --adopt mise
  $0 --backup-conflicts zsh mise
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

parse_args() {
  REQUESTED_DIRS=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -d | --dry-run)
        DRY_RUN=true
        shift
        ;;
      -a | --adopt)
        ADOPT=true
        shift
        ;;
      --backup-conflicts)
        BACKUP_CONFLICTS=true
        shift
        ;;
      --backup-dir)
        if [[ $# -lt 2 || -z "$2" ]]; then
          error "--backup-dir requires a path"
          usage 1
        fi
        BACKUP_DIR=$2
        shift 2
        ;;
      -l | --list)
        LIST_MODE=true
        shift
        ;;
      -h | --help)
        usage 0
        ;;
      -*)
        error "Unknown option: $1"
        usage 1
        ;;
      *)
        REQUESTED_DIRS+=("$1")
        shift
        ;;
    esac
  done
}

backup_conflicting_targets() {
  local -a dirs=("$@")
  local dir source relative target link_target backup_target
  local backup_root=$BACKUP_DIR

  for dir in "${dirs[@]}"; do
    [[ -d "$STOW_SH_DIR/$dir" ]] || continue

    while IFS= read -r -d '' source; do
      relative=${source#"$STOW_SH_DIR/$dir/"}
      target="$HOME/$relative"
      [[ -e "$target" || -L "$target" ]] || continue

      # Relative links resolving to the source are already Stow-managed. GNU
      # Stow rejects equivalent absolute links, so normalize those via backup.
      if [[ "$source" -ef "$target" ]]; then
        if [[ ! -L "$target" ]]; then
          continue
        fi
        link_target=$(readlink "$target")
        [[ "$link_target" == /* ]] || continue
      fi

      if [[ -z "$backup_root" ]]; then
        backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/n-dotfiles/stow-backups/$(date +%Y%m%d-%H%M%S)-$$"
      fi
      ACTIVE_BACKUP_ROOT=$backup_root
      backup_target="$backup_root/$relative"
      if [[ -e "$backup_target" || -L "$backup_target" ]]; then
        error "Backup target already exists: $backup_target"
        return 1
      fi

      mkdir -p "$(dirname "$backup_target")" || return 1
      mv "$target" "$backup_target" || return 1
      BACKED_UP_RELATIVE_PATHS+=("$relative")
      echo "Backed up $relative to $backup_target"
    done < <(find "$STOW_SH_DIR/$dir" \( -type f -o -type l \) -print0)
  done
}

restore_staged_backups() {
  local index relative target backup_path

  for ((index = ${#BACKED_UP_RELATIVE_PATHS[@]} - 1; index >= 0; index--)); do
    relative=${BACKED_UP_RELATIVE_PATHS[$index]}
    target="$HOME/$relative"
    backup_path="$ACTIVE_BACKUP_ROOT/$relative"
    if [[ -e "$target" || -L "$target" ]]; then
      error "Cannot restore backup because target now exists: $target"
      continue
    fi
    mkdir -p "$(dirname "$target")"
    mv "$backup_path" "$target"
    echo "Restored $target after failed preflight"
  done
}

stow_package() {
  local dir=$1
  shift
  local -a options=("$@")

  # Keep Omarchy's shared ~/.config tree as real directories. Without this,
  # Stow can fold a fresh ~/.config into a single package symlink.
  [[ "$dir" == "omarchy" ]] && options+=("--no-folding")
  stow "${options[@]}" "$dir"
}

validate_requested_dirs() {
  local dir known
  for dir in "${REQUESTED_DIRS[@]}"; do
    known=false
    for candidate in "${STOW_DIRS[@]}"; do
      [[ "$candidate" == "$dir" ]] && known=true && break
    done
    if [[ "$known" != "true" ]]; then
      error "Unknown stow package: $dir (use --list to see packages)"
      exit 1
    fi
  done
}

main() {
  parse_args "$@"

  if [[ "$ADOPT" == "true" && "$BACKUP_CONFLICTS" == "true" ]]; then
    error "--adopt and --backup-conflicts cannot be used together"
    exit 1
  fi
  if [[ "$DRY_RUN" == "true" && "$BACKUP_CONFLICTS" == "true" ]]; then
    error "--dry-run and --backup-conflicts cannot be used together"
    exit 1
  fi
  if [[ -n "$BACKUP_DIR" && "$BACKUP_CONFLICTS" != "true" ]]; then
    error "--backup-dir requires --backup-conflicts"
    exit 1
  fi

  if [[ "$LIST_MODE" == "true" ]]; then
    printf '%s\n' "${STOW_DIRS[@]}"
    exit 0
  fi

  if ! command -v stow >/dev/null 2>&1; then
    error "stow is not installed (macOS: brew install stow, Debian/Ubuntu: apt install stow)"
    exit 1
  fi

  local -a dirs=("${STOW_DIRS[@]}")
  if [[ ${#REQUESTED_DIRS[@]} -gt 0 ]]; then
    validate_requested_dirs
    dirs=("${REQUESTED_DIRS[@]}")
  fi

  if [[ "$BACKUP_CONFLICTS" == "true" ]]; then
    if ! backup_conflicting_targets "${dirs[@]}"; then
      restore_staged_backups
      return 1
    fi
  fi

  local -a stow_opts=(
    "--dir=$STOW_SH_DIR"
    "--target=$HOME"
    "--verbose=1"
    "-R"
  )
  [[ "$ADOPT" == "true" ]] && stow_opts+=("--adopt")
  [[ "$DRY_RUN" == "true" ]] && stow_opts+=("--no")

  local dir failed=0 preflight_output
  local -a preflight_opts

  # GNU Stow validates one invocation at a time. Preflight every requested
  # package before applying any of them so a late conflict cannot leave HOME
  # partially restowed.
  if [[ "$DRY_RUN" != "true" ]]; then
    for dir in "${dirs[@]}"; do
      [[ -d "$STOW_SH_DIR/$dir" ]] || continue
      preflight_opts=("${stow_opts[@]}" "--no")

      if ! preflight_output=$(stow_package "$dir" "${preflight_opts[@]}" 2>&1); then
        printf '%s\n' "$preflight_output" >&2
        error "Failed to preflight $dir"
        failed=1
      fi
    done
    if [[ "$failed" -ne 0 ]]; then
      [[ "$BACKUP_CONFLICTS" == "true" ]] && restore_staged_backups
      return "$failed"
    fi
  fi

  for dir in "${dirs[@]}"; do
    if [[ ! -d "$STOW_SH_DIR/$dir" ]]; then
      echo "Skipping missing package: $dir"
      continue
    fi

    if stow_package "$dir" "${stow_opts[@]}"; then
      echo "Stowed $dir"
    else
      error "Failed to stow $dir"
      failed=1
    fi
  done

  return "$failed"
}

main "$@"
