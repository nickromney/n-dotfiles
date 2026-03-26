#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
BIN_DIR="${BIN_DIR:-}"

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/build-browser-tools.sh [options]

Build the compiled `browser-tools` binary from `scripts/browser-tools.ts`.

Options:
  -b, --bin-dir <path>  Output directory for the compiled binary (default: ./bin)
  -d, --dry-run         Print the commands that would run without building
  -h, --help            Show this help message

Examples:
  scripts/build-browser-tools.sh
  scripts/build-browser-tools.sh --dry-run
  scripts/build-browser-tools.sh --bin-dir /tmp/browser-tools-bin
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would execute: $*"
    return 0
  fi

  "$@"
}

main() {
  local script_dir
  local repo_root

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"
  BIN_DIR="${BIN_DIR:-${repo_root}/bin}"

  while [[ $# -gt 0 ]]; do
    case $1 in
      -b|--bin-dir)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          BIN_DIR="$2"
          shift 2
        else
          error "--bin-dir requires a path"
          usage 1
        fi
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        error "Unknown option: $1"
        usage 1
        ;;
    esac
  done

  if [[ ! -f "${script_dir}/package.json" ]]; then
    error "Missing ${script_dir}/package.json for browser-tools dependencies."
    exit 1
  fi

  if ! command -v bun >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] Would require bun in PATH"
    else
      error "bun is required to build browser-tools."
      echo "Install bun: https://bun.sh" >&2
      exit 1
    fi
  fi

  if [[ ! -d "${script_dir}/node_modules/commander" ]] || [[ ! -d "${script_dir}/node_modules/puppeteer-core" ]]; then
    run_cmd bun install --cwd "${script_dir}"
  else
    echo "Dependencies already installed"
  fi

  run_cmd mkdir -p "$BIN_DIR"
  run_cmd bun build "${script_dir}/browser-tools.ts" --compile --target bun --outfile "${BIN_DIR}/browser-tools"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would build ${BIN_DIR}/browser-tools"
  else
    echo "Built ${BIN_DIR}/browser-tools"
  fi
}

main "$@"
