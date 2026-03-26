#!/usr/bin/env bash
# Installs the slicer CLI and slicer-mac bundle.
# Defaults to dry-run mode; pass --execute to install.

set -euo pipefail

DRY_RUN=true
FORCE=false
NO_TRAY=false

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: slicer-mac/install-slicer-mac.sh [options]

Install the slicer CLI plus the slicer-mac bundle and launchd service.
This script defaults to dry-run mode.

Options:
  -d, --dry-run  Preview the install steps without changing the machine
      --execute  Run the install for real
  -f, --force    Install over an existing slicer installation
  -h, --help     Show this help message
      --no-tray  Skip the slicer tray service

Examples:
  slicer-mac/install-slicer-mac.sh
  slicer-mac/install-slicer-mac.sh --execute
  slicer-mac/install-slicer-mac.sh --execute --force --no-tray
EOF

  exit "$exit_code"
}

expect_output() {
  local label="$1"
  local expected="$2"
  local output="$3"

  if echo "$output" | grep -qF "$expected"; then
    echo "  ok: $expected"
  else
    echo "ERROR: $label did not produce expected output." >&2
    echo "  expected: $expected" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --execute)
        DRY_RUN=false
        shift
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -f|--force)
        DRY_RUN=false
        FORCE=true
        shift
        ;;
      --no-tray)
        NO_TRAY=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage 1
        ;;
    esac
  done
}

main() {
  local found_count
  local bundle_output
  local mac_output

  if [[ $EUID -eq 0 ]]; then
    echo "Error: do not run as root. This script uses 'sudo' internally where needed." >&2
    exit 1
  fi

  parse_args "$@"

  SUDO_PATHS=(
    "/usr/local/bin/slicer"
    "/usr/local/bin/openapi.yaml"
  )

  USER_PATHS=(
    "$HOME/slicer"
    "$HOME/slicer-mac"
    "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.plist"
    "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.tray.plist"
  )

  found_sudo=()
  found_user=()

  for path in "${SUDO_PATHS[@]}"; do
    [[ -e "$path" ]] || [[ -L "$path" ]] && found_sudo+=("$path") || true
  done

  for path in "${USER_PATHS[@]}"; do
    [[ -e "$path" ]] || [[ -L "$path" ]] && found_user+=("$path") || true
  done

  found_count=$(( ${#found_sudo[@]} + ${#found_user[@]} ))

  if [[ $found_count -gt 0 ]]; then
    echo "Existing slicer artifacts found ($found_count):"
    for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
      echo "  [sudo] $path"
    done
    for path in "${found_user[@]+"${found_user[@]}"}"; do
      echo "  [user] $path"
    done
    echo ""
    if ! "$FORCE" && ! "$DRY_RUN"; then
      echo "Pass --force to install over existing, or run remove-slicer-mac.sh --execute first." >&2
      exit 1
    fi
  fi

  if "$DRY_RUN"; then
    echo "[dry-run] Would run:"
    echo "  curl -sLS https://get.slicervm.com | sudo bash"
    echo "  slicer version"
    echo "  slicer install slicer-mac $HOME/slicer-mac"
    if "$NO_TRAY"; then
      echo "  slicer-mac install --no-tray"
    else
      echo "  slicer-mac install"
    fi
    echo "  slicer-mac up"
    echo "  slicer vm list"
    echo ""
    if "$FORCE"; then
      echo "[dry-run] --force would install over existing artifacts."
    elif [[ $found_count -gt 0 ]]; then
      echo "[dry-run] Would be blocked by existing artifacts (pass --force to override)."
    fi
    echo ""
    echo "Pass --execute to install, or --force to install over existing."
    exit 0
  fi

  echo "==> Installing slicer CLI..."
  curl -sLS https://get.slicervm.com | sudo bash

  echo ""
  echo "==> Checking slicer version..."
  slicer version

  echo ""
  echo "==> Installing slicer-mac bundle to $HOME/slicer-mac..."
  bundle_output=$(slicer install slicer-mac "$HOME/slicer-mac" 2>&1 | tee /dev/stderr)

  expect_output "slicer install" \
    "Installed slicer-mac bundle to: $HOME/slicer-mac" \
    "$bundle_output"

  cd "$HOME/slicer-mac"
  export PATH="$HOME/slicer-mac:$PATH"

  if "$NO_TRAY"; then
    echo ""
    echo "==> Running slicer-mac install --no-tray..."
    mac_output=$(slicer-mac install --no-tray 2>&1 | tee /dev/stderr)
  else
    echo ""
    echo "==> Running slicer-mac install..."
    mac_output=$(slicer-mac install 2>&1 | tee /dev/stderr)
  fi

  expect_output "slicer-mac install" \
    "[INFO] Installed launchd plist at $HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.plist" \
    "$mac_output"

  expect_output "slicer-mac install" \
    "[INFO] user service started with launchd label com.openfaasltd.slicer-mac" \
    "$mac_output"

  echo ""
  echo "==> Starting slicer-mac..."
  slicer-mac up

  echo ""
  echo "==> Verifying (slicer vm list)..."
  slicer vm list

  echo ""
  echo "Done."
}

main "$@"
