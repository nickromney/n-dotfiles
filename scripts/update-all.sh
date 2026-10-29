#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: scripts/update-all.sh [--dry-run] [--no-cooldown] [--no-input] [--only COMPONENT]

Update installed Homebrew packages, mise pins, repository dependencies,
Mac App Store apps, and Rust toolchains. New mise/Bun/uv releases normally
wait seven days. Homebrew, mas, and rustup use their native update policies.
Major versions may change. Existing mise versions and Homebrew caches are kept.

Options:
  --dry-run         Preview without installing tools or writing pins/lockfiles
  --no-cooldown     Allow today's releases for this invocation only
  --no-input        Approve updates without an interactive confirmation
  --only COMPONENT  Run only mise, dependencies, brew, mas, or rust
  -h, --help        Show this help

A preview may contact registries and refresh their caches. Homebrew previews
use existing metadata; run scripts/brew-with-policy.sh update to refresh it.
Failures are reported per step and produce a nonzero exit status. Missing
optional host package managers are reported as skipped. AI CLI native installers
and operating-system updates remain separate from these managed components.

Examples:
  scripts/update-all.sh --dry-run
  scripts/update-all.sh --no-input
  scripts/update-all.sh --dry-run --no-cooldown
  scripts/update-all.sh --no-cooldown --no-input
  scripts/update-all.sh --only mise --no-cooldown --no-input
HELP
}

dry_run=false
no_input=false
age_days=7
only=all
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --no-cooldown) age_days=0 ;;
    --no-input) no_input=true ;;
    --only)
      [[ $# -ge 2 ]] || { echo 'Missing component after --only' >&2; exit 2; }
      only="$2"
      case "$only" in
        mise | dependencies | brew | mas | rust) ;;
        *) echo "Unknown component: $only" >&2; exit 2 ;;
      esac
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Preview commands must not let mise install a missing dependency implicitly.
export MISE_AUTO_INSTALL=0
export MISE_EXEC_AUTO_INSTALL=0

if [[ "$dry_run" != true && "$no_input" != true ]]; then
  printf 'Update %s with a %s-day release cooldown for mise/Bun/uv? [y/N] ' "$only" "$age_days"
  if ! IFS= read -r answer; then
    echo 'No input. Use --no-input to approve unattended updates.' >&2
    exit 1
  fi
  case "$answer" in
    y | Y | yes | YES) ;;
    *) echo 'Updates cancelled.'; exit 1 ;;
  esac
fi

failures=0
step() {
  local label="$1"
  shift
  printf '\n%s\n' "$label"
  if "$@"; then
    printf 'OK: %s\n' "$label"
  else
    printf 'FAILED: %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

selected() { [[ "$only" == all || "$only" == "$1" ]]; }

checked_registry_command() {
  local log status
  log="$(mktemp)" || return
  "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if [[ "$status" -ne 0 ]] || grep -Eq 'was not checked for updates:|Error getting latest version|Remote versions cannot be fetched|using the copy mise cached earlier|failed to write cache file' "$log"; then
    rm -f "$log"
    echo 'Update incomplete; check the registry errors above.' >&2
    return 1
  fi
  rm -f "$log"
}

update_mise() {
  command -v mise >/dev/null 2>&1 || { echo 'mise is required.' >&2; return 1; }
  if [[ ! "$repo_root/mise/.config/mise/config.toml" -ef "$HOME/.config/mise/config.toml" ]]; then
    echo 'Global mise config is not stowed from this repository. Run ./stow.sh first.' >&2
    return 1
  fi
  local args=(upgrade --global --bump --no-prune --minimum-release-age "${age_days}d")
  [[ "$dry_run" != true ]] || args+=(--dry-run)
  checked_registry_command mise "${args[@]}" || return
  if [[ "$dry_run" != true ]]; then
    checked_registry_command mise upgrade --global --bump --no-prune --minimum-release-age "${age_days}d" --dry-run-code
  fi
}

update_bun() {
  local args=(update --latest --minimum-release-age "$((age_days * 86400))")
  [[ "$dry_run" != true ]] || args+=(--dry-run)
  (cd scripts && checked_registry_command mise exec -- bun "${args[@]}") || return
  if [[ "$dry_run" == true ]]; then
    mise exec -- ./scripts/build-browser-tools.sh --dry-run
  else
    (cd scripts && mise exec -- bun audit) || return
    mise exec -- ./scripts/build-browser-tools.sh || return
    ./bin/browser-tools --help
  fi
}

update_uv() {
  local args=(lock --upgrade --exclude-newer "$age_days days")
  [[ "$dry_run" != true ]] || args+=(--dry-run)
  mise exec -- uv "${args[@]}" || return
  if [[ "$dry_run" != true ]]; then
    # uv records the override in its lockfile. Restore normal lock metadata
    # without silently losing a dependency selected by the emergency update.
    local snapshot before after
    snapshot="$(mktemp)" || return
    cp uv.lock "$snapshot" || return
    before="$(mise exec -- uv export --frozen --all-groups --all-extras --no-header --no-annotate)" || { rm -f "$snapshot"; return 1; }
    if ! mise exec -- uv lock --offline; then
      cp "$snapshot" uv.lock
      rm -f "$snapshot"
      return 1
    fi
    after="$(mise exec -- uv export --frozen --all-groups --all-extras --no-header --no-annotate)" || { cp "$snapshot" uv.lock; rm -f "$snapshot"; return 1; }
    if [[ "$before" != "$after" ]]; then
      cp "$snapshot" uv.lock
      rm -f "$snapshot"
      echo 'Updated Python dependencies require the emergency cutoff. uv.lock was retained; review the cutoff before normal --locked checks.' >&2
      return 1
    fi
    rm -f "$snapshot"
    mise exec -- uv audit --locked
  fi
}

update_brew() {
  local args=(package-manager --no-input --no-cleanup) remaining
  local brew_env=(env -u HOMEBREW_UPGRADE_GREEDY -u HOMEBREW_UPGRADE_GREEDY_CASKS)
  [[ "$dry_run" != true ]] || args+=(--dry-run)
  echo "Self-updating apps keep their native updater and release channel."
  "${brew_env[@]}" ./scripts/brew-update.sh "${args[@]}" || return
  if [[ "$dry_run" != true ]]; then
    remaining="$("${brew_env[@]}" HOMEBREW_NO_AUTO_UPDATE=1 ./scripts/brew-with-policy.sh outdated --quiet)" || return
    if [[ -n "$remaining" ]]; then
      printf 'Homebrew still reports outdated packages:\n%s\nClose running apps or review package pins, then rerun this component.\n' "$remaining" >&2
      return 1
    fi
  fi
}

update_mas() {
  local remaining
  if [[ "$dry_run" == true ]]; then
    mas outdated
  else
    mas upgrade || return
    remaining="$(mas outdated)" || return
    if [[ -n "$remaining" ]]; then
      printf 'Mac App Store apps still need updates:\n%s\n' "$remaining" >&2
      return 1
    fi
  fi
}

if selected brew; then
  if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    step 'Homebrew packages' update_brew
  elif [[ "$only" == brew ]]; then
    echo 'Homebrew updates require macOS and Homebrew.' >&2
    failures=$((failures + 1))
  else
    echo 'SKIP: Homebrew packages (macOS/Homebrew unavailable)'
  fi
fi

mise_step_failed=false
if selected mise; then
  failures_before_mise=$failures
  step 'Mise tools and pins' update_mise
  [[ "$failures" -eq "$failures_before_mise" ]] || mise_step_failed=true
fi

if selected dependencies; then
  if [[ "$mise_step_failed" == true ]]; then
    echo 'SKIP: dependency updates and rebuilds because the mise step failed.' >&2
  else
    step 'JavaScript dependencies' update_bun
    step 'Python dependency lockfile' update_uv
  fi
fi

if selected mas; then
  if [[ "$(uname -s)" == Darwin ]] && command -v mas >/dev/null 2>&1; then
    step 'Mac App Store apps' update_mas
  elif [[ "$only" == mas ]]; then
    echo 'Mac App Store updates require macOS and mas.' >&2
    failures=$((failures + 1))
  else
    echo 'SKIP: Mac App Store apps (macOS/mas unavailable)'
  fi
fi

if selected rust; then
  if command -v rustup >/dev/null 2>&1; then
    if [[ "$dry_run" == true ]]; then
      step 'Rust toolchain preview' rustup check
    else
      step 'Rust toolchains' rustup update
    fi
  elif [[ "$only" == rust ]]; then
    echo 'rustup is required for Rust toolchain updates.' >&2
    failures=$((failures + 1))
  else
    echo 'SKIP: Rust toolchains (rustup unavailable)'
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  printf '\nUpdate incomplete: %s step(s) failed.\n' "$failures" >&2
  exit 1
fi
if [[ "$dry_run" == true ]]; then
  echo 'Preview completed. No tools, pins, or lockfiles changed.'
else
  echo 'Selected managed updates completed. Restart existing shells/apps to use new versions.'
fi
