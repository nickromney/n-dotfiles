#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091,SC2034
set -euo pipefail

INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/install-lib.sh
source "$INSTALL_SH_DIR/scripts/install-lib.sh"

usage() {
  echo "Usage: $0 [options]"
  echo "Note: install.sh remains the standalone entrypoint for config-driven installs and updates."
  echo "Options:"
  echo "  -c, --config <name>     Add configuration file to install (can be used multiple times)"
  echo "  -C, --config-dir <dir>  Specify configuration directory (default: _configs)"
  echo "  -d, --dry-run           Show what would be installed without making changes"
  echo "  -f, --force             Force actions where supported"
  echo "  -h, --help              Show this help message"
  echo "  -s, --stow              Run stow after package operations"
  echo "  -u, --update            Update already installed packages"
  echo "  -v, --verbose           Show raw package-manager output"
  echo ""
  echo "Examples:"
  echo "  $0                              # Install common host tools (default)"
  echo "  $0 -c focus/vscode              # Install VSCode extensions"
  echo "  $0 -c host/personal -c focus/vscode"
  echo "  $0 -C /path/to/configs -c work"
  echo "  CONFIG_FILES=\"\" $0 -s            # Run stow only"
  exit 1
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
      usage
    fi
    ;;
  -C | --config-dir)
    if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
      CONFIG_DIR="$2"
      shift 2
    else
      echo "Error: --config-dir requires a directory path" >&2
      usage
    fi
    ;;
  -h | --help)
    usage
    ;;
  --source-only)
    SOURCE_ONLY=true
    shift
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
    usage
    ;;
  esac
done

if [[ "$SOURCE_ONLY" != "true" ]]; then
  trap 'cleanup_generated_manifests' EXIT
  main "$@"
fi
