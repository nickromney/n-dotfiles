#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-with-policy.sh <brew arguments...>

Runs brew with the repository's Homebrew tap trust policy.

The adapter keeps Homebrew's current default of allowing non-official taps
unless the caller has explicitly configured tap trust, and hides repeated tap
trust migration hints during update paths.

Policy:
  HOMEBREW_NO_ENV_HINTS=1 is applied to reduce repeated policy hints.
  HOMEBREW_NO_REQUIRE_TAP_TRUST=1 is applied unless the caller has already set
  HOMEBREW_REQUIRE_TAP_TRUST or HOMEBREW_NO_REQUIRE_TAP_TRUST.

Examples:
  scripts/brew-with-policy.sh update
  scripts/brew-with-policy.sh upgrade --cask
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

homebrew_policy_env=(HOMEBREW_NO_ENV_HINTS=1)

if [[ -z "${HOMEBREW_REQUIRE_TAP_TRUST:-}" && -z "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" ]]; then
  homebrew_policy_env+=(HOMEBREW_NO_REQUIRE_TAP_TRUST=1)
fi

exec env "${homebrew_policy_env[@]}" brew "$@"
