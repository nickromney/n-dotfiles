#!/usr/bin/env bash
# Audit installed packages against the repo's declarative sources:
# the Brewfile (brew formulae/casks/mas) and the global mise config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT_BASE="${OUT_BASE:-$REPO_ROOT/_audit/installed}"

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit-installed.sh [options]

Compare installed brew and mise artifacts against the repo's
declarative sources (Brewfile, mise/.config/mise/config.toml) and
write a timestamped report under `_audit/installed/`.

Options:
  -h, --help               Show this help message
  -o, --out-base <path>    Base directory for timestamped audit output

Examples:
  scripts/audit-installed.sh
  scripts/audit-installed.sh --out-base /tmp/n-dotfiles-audit

Generated files:
  brew-bundle-check.txt    Brewfile entries missing from this machine
  brew-unmanaged.txt       Installed leaves/casks absent from the Brewfile
  mise-status.txt          mise-managed tools and their install state
EOF

  exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -o | --out-base)
      if [[ -n "${2:-}" ]]; then
        OUT_BASE="$2"
        shift 2
      else
        echo "Error: --out-base requires a path" >&2
        usage 1
      fi
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage 1
      ;;
  esac
done

BREWFILE="$REPO_ROOT/Brewfile"
if [[ "$(uname -s)" != "Darwin" ]]; then
  BREWFILE="$REPO_ROOT/Brewfile.posix"
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="$OUT_BASE/$timestamp"
mkdir -p "$out_dir"

echo "Auditing against: $BREWFILE"
echo "Report directory: $out_dir"
echo

if command -v brew >/dev/null 2>&1; then
  echo "Checking Brewfile coverage (missing on this machine)..."
  brew bundle check --file "$BREWFILE" --verbose >"$out_dir/brew-bundle-check.txt" 2>&1 || true
  cat "$out_dir/brew-bundle-check.txt"
  echo

  echo "Finding installed packages not managed by the Brewfile..."
  {
    echo "# brew formulae (leaves) not in $BREWFILE"
    comm -23 \
      <(brew leaves | sort) \
      <(awk -F'"' '/^brew /{print $2}' "$BREWFILE" | awk -F'/' '{print $NF}' | sort)
    echo
    echo "# brew casks not in $BREWFILE"
    comm -23 \
      <(brew list --cask 2>/dev/null | sort) \
      <(awk -F'"' '/^cask /{print $2}' "$BREWFILE" | sort)
  } >"$out_dir/brew-unmanaged.txt"
  cat "$out_dir/brew-unmanaged.txt"
  echo
else
  echo "brew not found; skipping Homebrew audit" | tee "$out_dir/brew-bundle-check.txt"
fi

if command -v mise >/dev/null 2>&1; then
  echo "Recording mise tool status..."
  mise ls >"$out_dir/mise-status.txt" 2>&1 || true
  cat "$out_dir/mise-status.txt"
else
  echo "mise not found; skipping mise audit" | tee "$out_dir/mise-status.txt"
fi

echo
echo "Audit report written to $out_dir"
