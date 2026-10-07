#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Runs the repo local CI gate used by the pre-push hook.
EOF
}

hook_parse_standard_args "$@"
hook_require_execute_or_preview "would run pre-push local CI gate"

if hook_skip_requested; then
  hook_fail "skip_requested: verification did not execute"
  exit 1
fi

if [[ "${N_DOTFILES_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_fail "recursive_gate: verification did not execute"
  exit 1
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
n-dotfiles pre-push local CI gate

Running:
  uv run --locked make lint
  uv run --locked make test

Full acceptance requires every configured check.
Explicit skip and recursive execution requests refuse verification.
EOF

export N_DOTFILES_LOCAL_CI_IN_PROGRESS=1
failed_gate=""

if ! uv run --locked make lint; then
  failed_gate="uv run --locked make lint"
elif ! uv run --locked make test; then
  failed_gate="uv run --locked make test"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed"
