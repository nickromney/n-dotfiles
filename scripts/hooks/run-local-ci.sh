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
  hook_print_skip_and_exit
fi

if [[ "${N_DOTFILES_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_warn "N_DOTFILES_LOCAL_CI_IN_PROGRESS=1; skipping run-local-ci.sh to avoid recursive local CI"
  exit 0
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
n-dotfiles pre-push local CI gate

Running:
  make lint
  make test-install
  make test-macos
  ./install.sh -d -v

Skip only when you have a reason:
  LEFTHOOK=0 git push
  N_DOTFILES_SKIP_HOOKS=1 git push
  git push --no-verify
EOF

export N_DOTFILES_LOCAL_CI_IN_PROGRESS=1
failed_gate=""

if ! make lint; then
  failed_gate="make lint"
elif ! make test-install; then
  failed_gate="make test-install"
elif ! make test-macos; then
  failed_gate="make test-macos"
elif ! ./install.sh -d -v; then
  failed_gate="./install.sh -d -v"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed"
