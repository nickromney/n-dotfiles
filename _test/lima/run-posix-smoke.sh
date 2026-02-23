#!/usr/bin/env bash
set -euo pipefail

DEFAULT_POSIX_CONFIG_LIST="_configs/host/personal-posix.list"

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

load_posix_config_files() {
  local list_file="${POSIX_CONFIG_LIST_FILE:-$DEFAULT_POSIX_CONFIG_LIST}"

  if [[ -n "${POSIX_CONFIG_FILES:-}" ]]; then
    echo "$POSIX_CONFIG_FILES"
    return 0
  fi

  if [[ ! -f "$list_file" ]]; then
    echo "ERROR: POSIX config list not found: $list_file"
    exit 1
  fi

  local -a entries=()
  mapfile -t entries < <(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$list_file")

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "ERROR: POSIX config list is empty: $list_file"
    exit 1
  fi

  printf '%s\n' "${entries[@]}" | paste -sd' ' -
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
  brew install bats-core shellcheck stow yq

  local posix_config_files
  posix_config_files=$(load_posix_config_files)
  echo "Using POSIX config bundle: ${POSIX_CONFIG_LIST_FILE:-$DEFAULT_POSIX_CONFIG_LIST}"
  echo "Resolved configs: $posix_config_files"

  echo "Running non-mac install dry-run (POSIX configs only)..."
  CONFIG_FILES="$posix_config_files" ./install.sh -d

  echo "Running stow dry-run in isolated HOME (fresh-home assertion)..."
  local fresh_home stow_log
  fresh_home="$(mktemp -d)"
  stow_log="$(mktemp)"
  trap 'rm -rf "$fresh_home" "$stow_log"' RETURN

  if ! HOME="$fresh_home" XDG_CONFIG_HOME="$fresh_home/.config" CONFIG_FILES="" ./install.sh -d -s >"$stow_log" 2>&1; then
    cat "$stow_log"
    echo "ERROR: stow dry-run failed in isolated HOME."
    exit 1
  fi

  cat "$stow_log"
  if grep -Eq '× Error stowing|would cause conflicts|All operations aborted\.' "$stow_log"; then
    echo "ERROR: stow dry-run reported conflicts in isolated HOME."
    exit 1
  fi

  echo "Running install.sh BATS suite..."
  ./_test/run_install_tests.sh

  echo "Running shellcheck suite..."
  if [[ "${STRICT_SHELLCHECK:-false}" == "true" ]]; then
    ./_test/shellcheck.sh
  else
    ./_test/shellcheck.sh || echo "Non-blocking: shellcheck reported existing repo issues."
  fi

  echo "POSIX/non-mac smoke test completed successfully."
}

main "$@"
