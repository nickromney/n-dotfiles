#!/usr/bin/env bash
# Read-only check for whether 1Password's developer tooling (CLI + SSH
# agent + SSH signing) is ready to use, for the git identity this repo's
# git/.gitconfig expects: signingkey set, commit.gpgsign = true,
# gpg.format = ssh, gpg.ssh.program = ~/.local/bin/op-ssh-sign (the portable
# shim in git/.local/bin/op-ssh-sign that picks the right real 1Password
# binary per platform, so the tracked git config itself stays OS-agnostic).
#
# Never mutates anything. See setup-ssh-from-1password.sh and
# setup-gitconfig-from-1password.sh for the scripts that actually apply
# config once this reports ready, and omarchy/README.md's "Optional
# 1Password / SSH Git setup" section for the manual git config commands.

set -euo pipefail

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/check-1password-dev-tools.sh [options]

Check whether 1Password's CLI, SSH agent, and SSH-signing binary are set up
on this machine. Read-only: reports status, makes no changes.

Options:
  -h, --help          Show this help message
      --gitconfig <path>  Git config file to read gpg.ssh.program from
                          (default: git/.gitconfig next to this script's repo,
                          or ~/.gitconfig if that has been stowed)
      --signer-path <path>   Expected real op-ssh-sign path (default: platform-specific)
      --wrapper-path <path>  Expected portable shim path (default: ~/.local/bin/op-ssh-sign)

Examples:
  scripts/check-1password-dev-tools.sh
  scripts/check-1password-dev-tools.sh --gitconfig ~/.gitconfig
EOF

  exit "$exit_code"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITCONFIG_PATH=""
SIGNER_PATH_OVERRIDE=""
WRAPPER_PATH_OVERRIDE=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage 0
        ;;
      --gitconfig)
        if [[ -n "${2:-}" ]]; then
          GITCONFIG_PATH="$2"
          shift 2
        else
          echo "Error: --gitconfig requires a value" >&2
          usage 1
        fi
        ;;
      --gitconfig=*)
        GITCONFIG_PATH="${1#*=}"
        shift
        ;;
      --signer-path)
        if [[ -n "${2:-}" ]]; then
          SIGNER_PATH_OVERRIDE="$2"
          shift 2
        else
          echo "Error: --signer-path requires a value" >&2
          usage 1
        fi
        ;;
      --signer-path=*)
        SIGNER_PATH_OVERRIDE="${1#*=}"
        shift
        ;;
      --wrapper-path)
        if [[ -n "${2:-}" ]]; then
          WRAPPER_PATH_OVERRIDE="$2"
          shift 2
        else
          echo "Error: --wrapper-path requires a value" >&2
          usage 1
        fi
        ;;
      --wrapper-path=*)
        WRAPPER_PATH_OVERRIDE="${1#*=}"
        shift
        ;;
      *)
        echo "Error: Unknown option: $1" >&2
        usage 1
        ;;
    esac
  done
}

ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }
fail() { echo "FAIL $*"; }

# The platform's expected op-ssh-sign install path. Only the Linux path is
# independently verified (present on this repo's Omarchy test host); the
# macOS path is the one already trusted in the tracked git/.gitconfig.
expected_signer_path() {
  if [[ -n "$SIGNER_PATH_OVERRIDE" ]]; then
    echo "$SIGNER_PATH_OVERRIDE"
    return
  fi
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
  else
    echo "/opt/1Password/op-ssh-sign"
  fi
}

check_cli() {
  if ! command -v op >/dev/null 2>&1; then
    fail "1Password CLI (op) not found on PATH"
    if [[ "$OSTYPE" == darwin* ]]; then
      warn "  install: brew install --cask 1password-cli"
    else
      warn "  Omarchy's base install normally provides 1password-cli;"
      warn "  check the Omarchy Install menu (Super+Alt+Space) if missing."
    fi
    return 1
  fi
  ok "1Password CLI (op) found: $(command -v op)"
  return 0
}

check_signed_in() {
  if ! command -v op >/dev/null 2>&1; then
    return 1
  fi
  if op account list >/dev/null 2>&1 && [[ -n "$(op account list 2>/dev/null)" ]]; then
    ok "1Password CLI has a signed-in account"
    return 0
  fi
  fail "1Password CLI has no signed-in account"
  warn "  In the 1Password app: Settings > Developer > enable"
  warn "  'Integrate with 1Password CLI', then 'op signin'."
  return 1
}

check_ssh_agent() {
  local -a candidates=(
    "$HOME/.1password/agent.sock"
    "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/1password/agent.sock"
  )
  local sock
  for sock in "${candidates[@]}"; do
    if [[ -S "$sock" ]]; then
      ok "1Password SSH agent socket found: $sock"
      return 0
    fi
  done

  if [[ -n "${SSH_AUTH_SOCK:-}" ]] && command -v ssh-add >/dev/null 2>&1 && ssh-add -l >/dev/null 2>&1; then
    ok "An SSH agent is reachable at \$SSH_AUTH_SOCK (not confirmed to be 1Password's)"
    return 0
  fi

  fail "1Password SSH agent socket not found (checked: ${candidates[*]})"
  warn "  In the 1Password app: Settings > Developer > enable 'Use the SSH agent'."
  return 1
}

check_signer_binary() {
  local expected
  expected="$(expected_signer_path)"
  if [[ -x "$expected" ]]; then
    ok "op-ssh-sign binary found: $expected"
    return 0
  fi
  fail "op-ssh-sign binary not found at $expected"
  return 1
}

# git/.gitconfig points gpg.ssh.program at this portable shim (same literal
# value on every platform); the shim itself picks the platform-specific real
# binary checked by check_signer_binary. Default assumes the git stow
# package has been applied so ~/.local/bin/op-ssh-sign is a real symlink.
wrapper_shim_path() {
  if [[ -n "$WRAPPER_PATH_OVERRIDE" ]]; then
    echo "$WRAPPER_PATH_OVERRIDE"
  else
    echo "$HOME/.local/bin/op-ssh-sign"
  fi
}

check_wrapper_shim() {
  local shim
  shim="$(wrapper_shim_path)"
  if [[ -x "$shim" ]]; then
    ok "op-ssh-sign shim found: $shim"
    return 0
  fi
  fail "op-ssh-sign shim not found at $shim"
  warn "  Stow the git package: ./stow.sh git"
  return 1
}

check_gitconfig_signer_path() {
  local gitconfig="$GITCONFIG_PATH"
  if [[ -z "$gitconfig" ]]; then
    if [[ -f "$HOME/.gitconfig" ]]; then
      gitconfig="$HOME/.gitconfig"
    else
      gitconfig="$REPO_ROOT/git/.gitconfig"
    fi
  fi

  if [[ ! -f "$gitconfig" ]]; then
    warn "No git config found at $gitconfig to check gpg.ssh.program"
    return 1
  fi

  local configured
  configured="$(git config --file "$gitconfig" --get gpg.ssh.program 2>/dev/null || true)"
  # The tracked value is a literal ~/... string (git config does not expand
  # ~ on read-back), so compare against the same unexpanded form rather than
  # wrapper_shim_path's expanded $HOME path.
  # shellcheck disable=SC2088 # Intentionally unexpanded; see comment above.
  local expected="~/.local/bin/op-ssh-sign"
  if [[ -n "$WRAPPER_PATH_OVERRIDE" ]]; then
    expected="$WRAPPER_PATH_OVERRIDE"
  fi

  if [[ -z "$configured" ]]; then
    warn "$gitconfig has no gpg.ssh.program set"
    return 1
  fi

  if [[ "$configured" == "$expected" ]]; then
    ok "$gitconfig gpg.ssh.program points at the portable shim: $configured"
    return 0
  fi

  fail "$gitconfig gpg.ssh.program is '$configured', expected '$expected'"
  warn "  Fix: git config --file '$gitconfig' gpg.ssh.program '$expected'"
  warn "  Or disable signing until ready: git config --file '$gitconfig' commit.gpgsign false"
  return 1
}

main() {
  parse_args "$@"

  local failures=0
  check_cli || failures=$((failures + 1))
  check_signed_in || failures=$((failures + 1))
  check_ssh_agent || failures=$((failures + 1))
  check_signer_binary || failures=$((failures + 1))
  check_wrapper_shim || failures=$((failures + 1))
  check_gitconfig_signer_path || failures=$((failures + 1))

  echo
  if [[ "$failures" -eq 0 ]]; then
    echo "1Password developer tools look ready for SSH-signed git commits."
  else
    echo "$failures check(s) not ready — see FAIL/WARN lines above."
  fi

  return "$failures"
}

main "$@"
