#!/usr/bin/env bash
# Opt-in Chromium memory threshold for Brave on macOS.

set -euo pipefail

export LC_ALL=C

DEFAULTS_CMD="${BRAVE_POLICY_DEFAULTS:-defaults}"
DOMAIN="${BRAVE_POLICY_DOMAIN:-com.brave.Browser}"
KEY="${BRAVE_POLICY_KEY:-TotalMemoryLimitMb}"
LIMIT_MIB=2048
DRY_RUN=false
COMMAND=""

usage() {
  local exit_code="${1:-0}"
  cat <<'EOF'
Usage: scripts/configure-brave-memory.sh <on|off|status> [options]

Manage Brave's Chromium soft memory threshold on macOS. The threshold causes
Chromium to discard tabs after the limit is exceeded; it is not a hard cap.
Restart Brave after changing it and expect inactive tabs to reload.

Commands:
  on          Set the threshold (default: 2048 MiB)
  off         Remove the threshold and return to Brave defaults
  status      Show the configured threshold

Options:
  --limit <MiB>  Threshold for on; minimum 1024 MiB
  --dry-run      Show the planned change without writing defaults
  -h, --help     Show this help message

Examples:
  scripts/configure-brave-memory.sh on
  scripts/configure-brave-memory.sh on --limit 3072
  scripts/configure-brave-memory.sh off
EOF
  exit "$exit_code"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  [[ -n "${2:-}" ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    on | off | status)
      [[ -z "$COMMAND" ]] || die "Only one command may be supplied"
      COMMAND="$1"
      shift
      ;;
    --limit)
      require_value "$1" "${2:-}"
      [[ "$2" =~ ^[0-9]+$ ]] || die "--limit requires a positive integer"
      LIMIT_MIB="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      die "Unknown command: $1 (use --help)"
      ;;
  esac
done

[[ -n "$COMMAND" ]] || usage 1
[[ "$LIMIT_MIB" -ge 1024 ]] || die "--limit must be at least 1024 MiB"

read_policy() {
  "$DEFAULTS_CMD" read "$DOMAIN" "$KEY" 2>/dev/null || true
}

status() {
  local configured
  configured="$(read_policy)"
  if [[ "$configured" =~ ^[0-9]+$ ]]; then
    printf 'Brave memory policy: %s MiB\n' "$configured"
  else
    printf 'Brave memory policy: disabled\n'
  fi
}

case "$COMMAND" in
  status)
    status
    ;;
  on)
    if [[ "$DRY_RUN" == "true" ]]; then
      printf 'Would set Brave TotalMemoryLimitMb to %s MiB\n' "$LIMIT_MIB"
    else
      "$DEFAULTS_CMD" write "$DOMAIN" "$KEY" -int "$LIMIT_MIB"
      printf 'Brave memory policy: %s MiB (restart Brave to apply)\n' "$LIMIT_MIB"
    fi
    ;;
  off)
    if [[ "$DRY_RUN" == "true" ]]; then
      printf 'Would remove Brave TotalMemoryLimitMb\n'
    else
      "$DEFAULTS_CMD" delete "$DOMAIN" "$KEY" >/dev/null 2>&1 || true
      printf 'Brave memory policy: disabled (restart Brave to apply)\n'
    fi
    ;;
esac
