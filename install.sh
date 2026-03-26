#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091,SC2034
set -euo pipefail

INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/install-lib.sh
source "$INSTALL_SH_DIR/scripts/install-lib.sh"

usage() {
  local exit_code=${1:-0}

  cat <<EOF
Usage: $0 [options]

install.sh is the standalone entrypoint for config-driven installs, updates, and inventory.

Options:
  -c, --config <name>     Add configuration file to use (can be used multiple times)
  -C, --config-dir <dir>  Specify configuration directory (default: _configs)
  -d, --dry-run           Show what would change without making changes
  -f, --force             Force supported update/install operations where available
  -h, --help              Show this help message
  -l, --list              List available config bundles and tools as tab-separated rows
  -s, --stow              Run stow after package operations
  -u, --update            Update tools already installed from selected configs; missing tools are skipped
  -v, --verbose           Show raw package-manager output

Examples:
  $0
  $0 -c focus/vscode
  $0 -c host/personal -c focus/vscode
  $0 -u -c focus/typescript
  $0 --list
  $0 --list -c focus/ai
  $0 -C /path/to/configs -c host/common
  CONFIG_FILES="" $0 -s
EOF

  exit "$exit_code"
}

SOURCE_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  -s | --stow)
    STOW=true
    shift
    ;;
  -f | --force)
    FORCE=true
    shift
    ;;
  -l | --list)
    LIST_MODE=true
    shift
    ;;
  -u | --update)
    UPDATE=true
    shift
    ;;
  -c | --config)
    if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
      if [[ "$CONFIG_FILES_SET_VIA_CLI" == "false" ]]; then
        CONFIG_FILES=()
        CONFIG_FILES_SET_VIA_CLI=true
      fi
      CONFIG_FILES+=("$2")
      shift 2
    else
      echo "Error: --config requires a configuration name" >&2
      usage 1
    fi
    ;;
  -C | --config-dir)
    if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
      CONFIG_DIR="$2"
      shift 2
    else
      echo "Error: --config-dir requires a directory path" >&2
      usage 1
    fi
    ;;
  -h | --help)
    usage 0
    ;;
  --source-only)
    SOURCE_ONLY=true
    shift
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
    usage 1
    ;;
  esac
done

if [[ "${LIST_MODE:-false}" == "true" ]]; then
  if [[ "${STOW:-false}" == "true" || "${UPDATE:-false}" == "true" || "${FORCE:-false}" == "true" ]]; then
    echo "Error: --list cannot be combined with --stow, --update, or --force" >&2
    usage 1
  fi
fi

if [[ "$SOURCE_ONLY" != "true" ]]; then
  trap 'cleanup_generated_manifests' EXIT
  main "$@"
fi
