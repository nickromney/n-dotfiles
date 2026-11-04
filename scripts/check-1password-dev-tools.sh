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
      --diagnose-signing     Diagnose effective commit signing without contacting op
      --repo <path>          Repository to diagnose (default: current directory)

Examples:
  scripts/check-1password-dev-tools.sh
  scripts/check-1password-dev-tools.sh --gitconfig ~/.gitconfig
  scripts/check-1password-dev-tools.sh --diagnose-signing --repo ~/Developer/work/project
EOF

  exit "$exit_code"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITCONFIG_PATH=""
SIGNER_PATH_OVERRIDE=""
WRAPPER_PATH_OVERRIDE=""
DIAGNOSE_SIGNING=false
DIAGNOSTIC_REPO="."

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --diagnose-signing)
        DIAGNOSE_SIGNING=true
        shift
        ;;
      --repo)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          echo 'Error: --repo requires a path' >&2
          exit 1
        fi
        DIAGNOSTIC_REPO="$2"
        shift 2
        ;;
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

diagnose_signing() {
  if ! git -C "$DIAGNOSTIC_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    fail "Not a Git repository: $DIAGNOSTIC_REPO"
    return 1
  fi
  local setting key fingerprint listing sock agent_config failures=0
  echo "Effective commit-signing settings in $DIAGNOSTIC_REPO (origin followed by value):"
  for setting in user.signingkey commit.gpgsign gpg.format gpg.ssh.program; do
    echo "$setting:"
    git -C "$DIAGNOSTIC_REPO" config --show-origin --get "$setting" || true
  done
  agent_config="${XDG_CONFIG_HOME:-$HOME/.config}/1Password/ssh/agent.toml"
  echo "1Password agent config: $agent_config"
  if [[ -L "$agent_config" ]]; then
    echo "Config symlink: $(readlink "$agent_config")"
  elif [[ ! -f "$agent_config" ]]; then
    warn 'No agent.toml at this path; default vault selection applies'
  fi
  key="$(git -C "$DIAGNOSTIC_REPO" config --get user.signingkey || true)"
  if [[ -z "$key" ]]; then
    fail 'No effective user.signingkey; configure the public key from the intended 1Password signing item'
    return 1
  fi
  case "$key" in
    ssh-*|ecdsa-*|sk-*) fingerprint="$(printf '%s\n' "$key" | ssh-keygen -lf - 2>/dev/null)" || fingerprint="" ;;
    *)
      key="$(git -C "$DIAGNOSTIC_REPO" config --path --get user.signingkey)"
      [[ "$key" == /* ]] || key="$DIAGNOSTIC_REPO/$key"
      fingerprint="$(ssh-keygen -lf "$key" 2>/dev/null)" || fingerprint=""
      ;;
  esac
  fingerprint="$(printf '%s\n' "$fingerprint" | awk '{print $2}')"
  if [[ -z "$fingerprint" ]]; then
    fail 'Could not fingerprint user.signingkey as an SSH public key or public-key file'
    return 1
  fi
  echo "Signing-key fingerprint: $fingerprint"
  local -a sockets=("${SSH_AUTH_SOCK:-}" "$HOME/.1password/agent.sock")
  if [[ "$OSTYPE" == darwin* ]]; then
    sockets+=("$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock")
  else
    sockets+=("${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/1password/agent.sock")
  fi
  for sock in "${sockets[@]}"; do
    [[ -n "$sock" ]] || continue
    echo "Agent socket: $sock"
    if listing="$(SSH_AUTH_SOCK="$sock" ssh-add -l 2>&1)"; then
      printf '%s\n' "$listing"
      if printf '%s\n' "$listing" | awk -v fp="$fingerprint" '$2 == fp { found=1 } END { exit !found }'; then
        ok 'Configured signing key is offered by this agent'
      else
        fail 'Configured signing key is absent from this agent'
        failures=$((failures + 1))
      fi
    else
      warn "Cannot list keys: $listing"
      failures=$((failures + 1))
    fi
  done
  echo 'A matching fingerprint proves key availability, not permission to sign.'
  echo 'If it matches but commits fail, inspect 1Password authorization and the effective gpg.ssh.program above.'
  return "$failures"
}

main() {
  parse_args "$@"
  if [[ "$DIAGNOSE_SIGNING" == "true" ]]; then
    diagnose_signing
    return "$?"
  fi

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
