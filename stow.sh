#!/usr/bin/env bash
# Symlink dotfiles into $HOME with GNU Stow.
#
# This is the only entrypoint a stow-only machine (e.g. work) needs:
#   git clone <repo> && cd n-dotfiles && ./stow.sh

set -euo pipefail

STOW_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each directory is a GNU Stow package targeting $HOME.
STOW_DIRS=(
  aerospace
  agents
  aws
  bash
  bat
  claude
  codex
  factory
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

DRY_RUN=false
ADOPT=false
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
  -l, --list      List available stow packages
  -h, --help      Show this help message

Examples:
  $0
  $0 --dry-run
  $0 zsh git
  $0 --adopt mise
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

  local -a stow_opts=(
    "--dir=$STOW_SH_DIR"
    "--target=$HOME"
    "--verbose=1"
    "-R"
  )
  [[ "$ADOPT" == "true" ]] && stow_opts+=("--adopt")
  [[ "$DRY_RUN" == "true" ]] && stow_opts+=("--no")

  local dir failed=0
  for dir in "${dirs[@]}"; do
    if [[ ! -d "$STOW_SH_DIR/$dir" ]]; then
      echo "Skipping missing package: $dir"
      continue
    fi

    if stow "${stow_opts[@]}" "$dir"; then
      echo "Stowed $dir"
    else
      error "Failed to stow $dir"
      failed=1
    fi
  done

  return "$failed"
}

main "$@"
