#!/usr/bin/env bash
set -euo pipefail

resolve_repo_dir() {
  local repo_hint=${1:-}

  if [[ -n "$repo_hint" && -d "$repo_hint" ]]; then
    echo "$repo_hint"
    return 0
  fi

  local base found
  for base in "$HOME" /Users /home; do
    found=$(find "$base" -maxdepth 6 -path "*/n-dotfiles" -type d 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
      echo "$found"
      return 0
    fi
  done

  return 1
}

enable_linuxbrew() {
  if [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
  elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$("/home/linuxbrew/.linuxbrew/bin/brew" shellenv)"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew is not available in this VM."
    exit 1
  fi
}

main() {
  local repo_dir
  repo_dir=$(resolve_repo_dir "${1:-}") || {
    echo "ERROR: Could not locate n-dotfiles repo inside VM."
    exit 1
  }

  echo "Using repo: $repo_dir"
  cd "$repo_dir"

  enable_linuxbrew

  echo "Installing Linux test dependencies via Homebrew..."
  brew install bats-core shellcheck stow mise

  echo "Validating Brewfile.posix parses via brew bundle list..."
  brew bundle list --file Brewfile.posix >/dev/null

  echo "Running stow dry-run in isolated HOME (fresh-home assertion)..."
  local fresh_home stow_log
  fresh_home="$(mktemp -d)"
  stow_log="$(mktemp)"
  trap 'rm -rf "$fresh_home" "$stow_log"' RETURN

  if ! HOME="$fresh_home" XDG_CONFIG_HOME="$fresh_home/.config" ./stow.sh --dry-run >"$stow_log" 2>&1; then
    cat "$stow_log"
    echo "ERROR: stow dry-run failed in isolated HOME."
    exit 1
  fi

  cat "$stow_log"
  if grep -Eq 'Failed to stow|would cause conflicts|All operations aborted\.' "$stow_log"; then
    echo "ERROR: stow dry-run reported conflicts in isolated HOME."
    exit 1
  fi

  echo "Validating global mise config parses in isolated HOME..."
  HOME="$fresh_home" XDG_CONFIG_HOME="$fresh_home/.config" ./stow.sh mise >/dev/null
  HOME="$fresh_home" XDG_CONFIG_HOME="$fresh_home/.config" mise ls >/dev/null

  echo "Running CLI contract BATS suite..."
  bats _test/cli-contracts.bats

  echo "Running Makefile BATS suite..."
  bats _test/makefile.bats

  echo "Running shellcheck suite..."
  if [[ "${STRICT_SHELLCHECK:-false}" == "true" ]]; then
    ./_test/shellcheck.sh
  else
    ./_test/shellcheck.sh || echo "Non-blocking: shellcheck reported existing repo issues."
  fi

  echo "POSIX/non-mac smoke test completed successfully."
}

main "$@"
