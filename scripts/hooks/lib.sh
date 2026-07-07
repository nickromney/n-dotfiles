#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Sourced hook scripts consume this shared root.
HOOKS_REPO_ROOT="$(cd "${HOOKS_DIR}/../.." && pwd)"

hook_skip_requested() {
  [[ "${N_DOTFILES_SKIP_HOOKS:-}" == "1" ]]
}

hook_print_skip_and_exit() {
  echo "WARN N_DOTFILES_SKIP_HOOKS=1; skipping ${0##*/}"
  exit 0
}

hook_ok() {
  echo "OK   $*"
}

hook_warn() {
  echo "WARN $*"
}

hook_fail() {
  echo "FAIL $*" >&2
}

hook_parse_standard_args() {
  HOOK_EXECUTE=0
  HOOK_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute)
        HOOK_EXECUTE=1
        ;;
      --dry-run)
        HOOK_EXECUTE=0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        HOOK_ARGS+=("$@")
        break
        ;;
      -*)
        hook_fail "unknown option: $1"
        usage >&2
        exit 1
        ;;
      *)
        HOOK_ARGS+=("$1")
        ;;
    esac
    shift
  done
}

hook_require_execute_or_preview() {
  local summary="$1"

  if [[ "${HOOK_EXECUTE}" != "1" ]]; then
    echo "DRY-RUN ${summary}"
    exit 0
  fi
}
