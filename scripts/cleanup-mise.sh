#!/usr/bin/env bash
# Delegate runtime/cache cleanup to mise, preserving repository-managed pins.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=true
ALL=false
CACHE_ONLY=false
PRUNE_ONLY=false
MODE=""
usage() {
  cat <<'HELP'
Usage: scripts/cleanup-mise.sh [options]

Preview unused mise tool versions and the mise cache by default.
Execution uses mise prune --tools and mise cache clear; it never recursively
removes ~/.local. Configured versions in mise's tracked configs are retained.
Pruning requires the global config to be stowed from this repository.
Versions used only by untracked projects, environment variables or ad-hoc
mise exec commands may be pruned. Review the preview before execution.

Options:
  -d, --dry-run   Preview only (default)
      --execute   Apply cleanup; requires a scope below
      --all       Prune unused tool versions and clear mise's cache
      --cache-only Clear cache only; preserve every installed tool version
      --prune-only Prune unused versions only; retain cache
      --no-input  No prompts; --execute is explicit deletion consent
  -h, --help      Show this help with examples

Run without sudo. Uses mise's configured data/cache paths. Global config:
${MISE_GLOBAL_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml}
After cache clearing, mise may download metadata and rebuild cached task output.
This does not edit config pins, install tools, or remove other ~/.local data.

Examples:
  scripts/cleanup-mise.sh --dry-run --all
  scripts/cleanup-mise.sh --execute --all --no-input
  scripts/cleanup-mise.sh --execute --cache-only
  scripts/cleanup-mise.sh --dry-run --prune-only
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --execute|-d|--dry-run)
      mode="$1"; [[ "$mode" == -d ]] && mode=--dry-run
      if [[ -n "$MODE" && "$MODE" != "$mode" ]]; then
        echo "Cannot combine --execute and --dry-run" >&2; exit 1
      fi
      MODE="$mode"; [[ "$mode" == --execute ]] && DRY_RUN=false
      shift ;;
    --all) ALL=true; shift ;;
    --cache-only) CACHE_ONLY=true; shift ;;
    --prune-only) PRUNE_ONLY=true; shift ;;
    --no-input) shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
scopes=0
for scope in "$ALL" "$CACHE_ONLY" "$PRUNE_ONLY"; do
  if "$scope"; then scopes=$((scopes+1)); fi
done
if [[ $scopes -gt 1 ]]; then echo "Select only one cleanup scope" >&2; exit 1; fi
if ! "$DRY_RUN" && [[ $scopes -eq 0 ]]; then
  echo "--execute requires --all, --cache-only or --prune-only" >&2; exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then echo "Run as your login user, without sudo" >&2; exit 1; fi
if ! command -v mise >/dev/null 2>&1; then echo "mise is required" >&2; exit 1; fi

if ! "$CACHE_ONLY"; then
  global_config="${MISE_GLOBAL_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml}"
  repo_config="$REPO_ROOT/mise/.config/mise/config.toml"
  if [[ ! "$global_config" -ef "$repo_config" ]]; then
    echo "Refusing runtime pruning: global mise config is not stowed from this repository." >&2
    echo "Apply ./stow.sh mise, or use --cache-only." >&2
    exit 1
  fi
  echo "Previewing unused versions (repo pins and other tracked configs retained):"
  mise prune --tools --dry-run
fi
if ! "$PRUNE_ONLY"; then
  cache_path=$(mise cache path) || { echo "Cannot determine mise cache path" >&2; exit 1; }
  echo "[cache] $cache_path"
  if [[ -d "$cache_path" ]]; then du -sh "$cache_path" 2>/dev/null || true; fi
fi
if "$DRY_RUN"; then
  if ! "$PRUNE_ONLY"; then echo "[dry-run] Would run: mise cache clear"; fi
  echo "[dry-run] No changes made. Use --execute with an explicit scope."
  exit 0
fi
if ! "$CACHE_ONLY"; then mise --yes prune --tools; fi
if ! "$PRUNE_ONLY"; then mise --yes cache clear; fi
echo "Done."
