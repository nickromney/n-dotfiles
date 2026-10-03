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
  herdr
  git
  kitty
  mise
  nushell
  nvim
  prettier
  silo
  ssh
  starship
  tmux
  yazi
  zsh
)

# Keep host-specific app and desktop configuration off the other platform.
# In particular, a Mac sync must never touch Omarchy's Hyprland/keyd paths.
case "$(uname -s)" in
  Darwin) STOW_DIRS+=(aerospace audio-priority-bar macos-borders) ;;
  Linux) STOW_DIRS+=(omarchy) ;;
esac

DRY_RUN=false
ADOPT=false
RESTOW=false
BACKUP_CONFLICTS=false
BACKUP_DIR=""
ACTIVE_BACKUP_ROOT=""
BACKED_UP_RELATIVE_PATHS=()
LIST_MODE=false

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options] [package ...]

Symlink dotfile packages into \$HOME using GNU Stow.
With no package arguments, all packages are stowed.

Options:
  -d, --dry-run   Show what would change without making changes
  -a, --adopt     Adopt pre-existing files into the repo (review with git diff!)
  -R, --restow    Explicitly prune stale links and recreate managed links
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
  $0 --restow zsh
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
      -R | --restow)
        RESTOW=true
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
  local dir plan line relative target backup_target
  local backup_root=$BACKUP_DIR
  local -a plan_opts=(
    "--dir=$STOW_SH_DIR"
    "--target=$HOME"
    "--verbose=2"
    "--stow"
    "--adopt"
    "--no"
  )

  for dir in "${dirs[@]}"; do
    [[ -d "$STOW_SH_DIR/$dir" ]] || continue

    if ! plan=$(stow_package "$dir" "${plan_opts[@]}" 2>&1); then
      printf '%s\n' "$plan" >&2
      return 1
    fi

    while IFS= read -r line; do
      [[ "$line" == "MV: "* ]] || continue
      relative=${line#"MV: "}
      relative=${relative%% -> *}
      target="$HOME/$relative"

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
    done <<<"$plan"
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

  # Keep machine-local state outside the repository. Folding ~/.aws would
  # redirect future credential/cache writes into this package.
  case "$dir" in
    aws | gh | nushell | ssh | omarchy) options+=("--no-folding") ;;
  esac
  stow "${options[@]}" "$dir"
}

legacy_n_borders_link_is_managed() {
  local path="$1"
  local target

  [[ -L "$path" ]] || return 1
  target="$(readlink "$path" 2>/dev/null || true)"
  case "$target" in
    */macos-borders/.config/n-borders | \
      */macos-borders/.config/n-borders/* | \
      */macos-borders/.local/bin/n-borders | \
      */macos-borders/.local/share/n-borders | \
      */macos-borders/.local/share/n-borders/*)
      return 0
      ;;
  esac
  return 1
}

legacy_n_borders_plist_is_managed() {
  local plist="$1"

  [[ -f "$plist" ]] || return 1
  grep -Fq '<key>Label</key><string>com.nickromney.n-borders</string>' "$plist" \
    && grep -Fq '.local/bin/n-borders-daemon' "$plist"
}

remove_legacy_n_borders() {
  local -a legacy_paths=(
    "$HOME/.config/n-borders"
    "$HOME/.config/n-borders/borders.conf"
    "$HOME/.local/bin/n-borders"
    "$HOME/.local/share/n-borders"
    "$HOME/.local/share/n-borders/LICENSE.omacosy"
    "$HOME/.local/share/n-borders/borders.swift"
  )
  local legacy_plist="$HOME/Library/LaunchAgents/com.nickromney.n-borders.plist"
  local legacy_daemon="$HOME/.local/bin/n-borders-daemon"
  local launchctl_cmd="${STOW_LAUNCHCTL_CMD:-launchctl}"
  local user_id="${STOW_UID:-$(id -u)}"
  local path
  local -a managed_paths=()
  local plist_managed=false
  local daemon_managed=false

  [[ "$(uname -s)" == "Darwin" ]] || return 0

  for path in "${legacy_paths[@]}"; do
    if legacy_n_borders_link_is_managed "$path"; then
      managed_paths+=("$path")
    fi
  done

  if legacy_n_borders_plist_is_managed "$legacy_plist"; then
    plist_managed=true
  fi

  # The compiled daemon has no Stow link provenance. Only a LaunchAgent with
  # our label and daemon command proves ownership of an ordinary file.
  if [[ "$plist_managed" == "true" && -f "$legacy_daemon" && ! -L "$legacy_daemon" ]]; then
    daemon_managed=true
  elif legacy_n_borders_link_is_managed "$legacy_daemon"; then
    daemon_managed=true
  fi

  if [[ ${#managed_paths[@]} -eq 0 && "$plist_managed" != "true" && "$daemon_managed" != "true" ]]; then
    return 0
  fi

  echo "Removing legacy n-borders integration"

  if [[ "$plist_managed" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would unload gui/$user_id/com.nickromney.n-borders"
      echo "Would remove $legacy_plist"
    else
      if command -v "$launchctl_cmd" >/dev/null 2>&1; then
        "$launchctl_cmd" bootout "gui/$user_id/com.nickromney.n-borders" >/dev/null 2>&1 || true
      fi
      rm -f "$legacy_plist"
    fi
  fi

  for path in ${managed_paths[@]+"${managed_paths[@]}"}; do
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would remove $path"
    else
      rm -f "$path"
    fi
  done

  if [[ "$daemon_managed" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would remove $legacy_daemon"
    else
      rm -f "$legacy_daemon"
    fi
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    rmdir "$HOME/.config/n-borders" "$HOME/.local/share/n-borders" 2>/dev/null || true
  fi
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

validate_runtime_roots() {
  local dir relative target source
  for dir in "$@"; do
    case "$dir" in
      aws) relative=.aws ;;
      gh) relative=.config/gh ;;
      nushell) relative='Library/Application Support/nushell' ;;
      ssh) relative=.ssh ;;
      *) continue ;;
    esac
    target="$HOME/$relative"
    source="$STOW_SH_DIR/$dir/$relative"
    [[ -d "$target" && -d "$source" ]] || continue
    if [[ "$(cd "$target" && pwd -P)" == "$(cd "$source" && pwd -P)" ]]; then
      error "$relative routes machine-local state into the repository."
      error "Preserve its local contents in a real HOME directory before stowing $dir."
      return 1
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

  validate_runtime_roots "${dirs[@]}" || return 1

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
  )
  if [[ "$RESTOW" == "true" ]]; then
    stow_opts+=("--restow")
  else
    stow_opts+=("--stow")
  fi
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
      if [[ "$dir" == "macos-borders" ]]; then
        remove_legacy_n_borders
      fi
    else
      error "Failed to stow $dir"
      failed=1
    fi
  done

  return "$failed"
}

main "$@"
