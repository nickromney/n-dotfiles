#!/usr/bin/env bash
# Preview and clear a bounded catalog of caches and explicitly selected old data.
set -euo pipefail
DRY_RUN=true
ALL=false
REPORT=false
LIST=false
TARGETS=()
MODE=""
INTERACTIVE=false
NO_INPUT=false
ARG_COUNT=$#

usage() {
  cat <<'HELP'
Usage: scripts/cleanup-storage.sh [options]

With no options in a terminal, shows an interactive menu with sizes and choices.
Deletion requires a selection, preview and confirmation. Outside a terminal,
defaults to a preview. --all selects only these caches:
Homebrew downloads, Go build cache, node-gyp, Selenium browsers, pre-commit,
Rod browsers, act downloads and Yarn Berry package cache.
Close builds and tools using these caches before executing; subsequent use may
rebuild or download files. --execute permanently deletes the displayed paths.

Models, Factory history/settings, installed runtimes, project files, Docker
volumes and chat history are excluded from --all. Optional named targets:
  huggingface   Downloaded models under the XDG cache directory
  omlx-models   ~/.omlx/models (local models)
  factory-logs ~/.factory/logs
  factory-data ~/.factory (all history, snapshots, settings and local tools)

Options:
  -d, --dry-run       Preview paths and sizes (default)
      --execute       Delete; requires --all or --target NAME
      --all           Clear the defined rebuildable cache set
      --target NAME   Select a catalog target (repeatable; see --list)
      --list          Show every target and its path; do not delete
      --report        Show sizes of major storage directories; do not delete
      --interactive   Show the chooser (also supports piped answers)
      --no-input      Disable chooser; --execute is explicit deletion consent
  -h, --help          Show this help with examples

Run as your login user, without sudo. HOME and XDG_CACHE_HOME must be absolute.
Symlinked target directories are refused during execution. Size totals are
estimates: APFS clones, sparse files and inaccessible data affect accounting.

Examples:
  scripts/cleanup-storage.sh
  scripts/cleanup-storage.sh --report
  scripts/cleanup-storage.sh --list
  scripts/cleanup-storage.sh --dry-run --all
  scripts/cleanup-storage.sh --execute --all --no-input
  scripts/cleanup-storage.sh --dry-run --target factory-data
  scripts/cleanup-storage.sh --execute --target factory-logs
  scripts/cleanup-storage.sh --execute --target huggingface --target omlx-models
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --execute|-d|--dry-run)
      next_mode="$1"; [[ "$next_mode" == -d ]] && next_mode=--dry-run
      if [[ -n "$MODE" && "$MODE" != "$next_mode" ]]; then
        echo "Cannot combine --execute and --dry-run" >&2; exit 1
      fi
      MODE="$next_mode"; [[ "$MODE" == --execute ]] && DRY_RUN=false
      shift ;;
    --all) ALL=true; shift ;;
    --report) REPORT=true; shift ;;
    --list) LIST=true; shift ;;
    --target)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "--target requires a catalog name (see --list)" >&2; exit 1
      fi
      TARGETS+=("$2"); shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --no-input) NO_INPUT=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
if "$INTERACTIVE" && { "$NO_INPUT" || [[ -n "$MODE" ]] || "$ALL" || "$REPORT" || "$LIST" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use --interactive on its own" >&2; exit 1
fi
if [[ $ARG_COUNT -eq 0 && -t 0 && -t 1 ]]; then INTERACTIVE=true; fi
if { "$REPORT" || "$LIST"; } && { ! "$DRY_RUN" || "$ALL" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use --report or --list without cleanup selections or --execute" >&2; exit 1
fi
if "$REPORT" && "$LIST"; then
  echo "Use either --report or --list" >&2; exit 1
fi
if "$ALL" && [[ ${#TARGETS[@]} -gt 0 ]]; then
  echo "Use either --all or --target" >&2; exit 1
fi
if ! "$DRY_RUN" && ! "$ALL" && [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "--execute requires --all or --target NAME" >&2; exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your login user, without sudo" >&2; exit 1
fi
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ "$HOME" != /* || "$HOME" == / || "$CACHE_ROOT" != /* || "$CACHE_ROOT" == / ]]; then
  echo "HOME and XDG_CACHE_HOME must be absolute, non-root directories" >&2; exit 1
fi
if [[ "$(uname -s)" == Darwin ]]; then
  APP_CACHE="$HOME/Library/Caches"
else
  APP_CACHE="$CACHE_ROOT"
fi
names=(homebrew go-build node-gyp selenium pre-commit rod act actcache yarn huggingface omlx-models factory-logs factory-data)
paths=("$APP_CACHE/Homebrew" "$APP_CACHE/go-build" "$APP_CACHE/node-gyp" "$CACHE_ROOT/selenium" "$CACHE_ROOT/pre-commit" "$CACHE_ROOT/rod" "$CACHE_ROOT/act" "$CACHE_ROOT/actcache" "$HOME/.yarn/berry/cache" "$CACHE_ROOT/huggingface" "$HOME/.omlx/models" "$HOME/.factory/logs" "$HOME/.factory")
if "$INTERACTIVE"; then
  descriptions=(
    "Homebrew downloaded packages; downloads again"
    "Go build output; rebuilds"
    "Node build headers; downloads again"
    "Selenium browser downloads; downloads again"
    "pre-commit environments; rebuilds"
    "Rod browser downloads; downloads again"
    "act downloads; downloads again"
    "act cached downloads; downloads again"
    "Yarn packages; downloads again"
    "Hugging Face model downloads; may need large downloads again"
    "oMLX local models; permanently removes local model files"
    "Factory logs only; keeps history and settings"
    "ALL Factory data: history, snapshots, settings, logs and local tools"
  )
  choices=()
  echo "Storage cleanup — select only items you no longer need."
  echo "Close builds and tools using these files before deleting."
  for ((i=0; i<${#names[@]}; i++)); do
    path="${paths[i]}"
    [[ -e "$path" || -L "$path" ]] || continue
    choices+=("${names[i]}")
    size=$(du -sh "$path" 2>/dev/null | cut -f 1) || size="unknown"
    printf '%2d) %-14s %s\n    %s\n    %s\n' "${#choices[@]}" "${names[i]}" "$size" "${descriptions[i]}" "$path"
  done
  if [[ ${#choices[@]} -eq 0 ]]; then echo "Nothing to clean."; exit 0; fi
  echo "Enter item numbers separated by spaces (blank or 0 cancels):"
  if ! read -r answer || [[ -z "$answer" || "$answer" == 0 ]]; then
    echo "Cancelled. No changes made."; exit 0
  fi
  selection=()
  read -r -a numbers <<< "$answer"
  for number in "${numbers[@]}"; do
    if [[ ! "$number" =~ ^[1-9][0-9]?$ ]] || [[ "$number" -gt ${#choices[@]} ]]; then
      echo "Invalid selection: $number. No changes made." >&2; exit 1
    fi
    selection+=(--target "${choices[number-1]}")
  done
  script_path="${BASH_SOURCE[0]}"
  bash "$script_path" --dry-run "${selection[@]}"
  echo "Permanently delete these selected paths? Type yes to confirm:"
  if ! read -r confirmation || [[ "$confirmation" != yes ]]; then
    echo "Cancelled. No changes made."; exit 0
  fi
  exec bash "$script_path" --execute --no-input "${selection[@]}"
fi
if "$LIST"; then
  for ((i=0; i<${#names[@]}; i++)); do printf '%-14s %s\n' "${names[i]}" "${paths[i]}"; done
  exit 0
fi
if "$REPORT"; then
  df -h "$HOME"
  echo "Directory sizes (do not add overlapping entries):"
  report_paths=("$HOME/Library" "$HOME/Developer" "$CACHE_ROOT" "$HOME/.local" "$HOME/.codex" "$HOME/Pictures" "$HOME/.omlx" "$HOME/go" "$HOME/Documents" "$HOME/.arkade" "$HOME/.yarn" "$HOME/.rustup" "$HOME/Downloads" "$HOME/.factory" "$HOME/.lima")
  for path in "${report_paths[@]}"; do
    [[ -d "$path" ]] || continue
    du -sh "$path" || echo "Could not fully measure: $path" >&2
  done
  exit 0
fi
# Resolve and validate the entire selection before deleting anything.
for requested in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  known=false
  for name in "${names[@]}"; do [[ "$requested" == "$name" ]] && known=true; done
  if ! "$known"; then echo "Unknown target: $requested (see --list)" >&2; exit 1; fi
done
selected=()
for ((i=0; i<${#names[@]}; i++)); do
  include=false
  if "$ALL" || [[ ${#TARGETS[@]} -eq 0 ]]; then
    [[ $i -lt 9 ]] && include=true
  else
    for requested in "${TARGETS[@]}"; do [[ "$requested" == "${names[i]}" ]] && include=true; done
  fi
  "$include" || continue
  path="${paths[i]}"
  [[ -e "$path" || -L "$path" ]] || continue
  if ! "$DRY_RUN"; then
    ancestor="$path"
    while [[ "$ancestor" != / ]]; do
      if [[ -L "$ancestor" ]]; then
        echo "Refusing symlinked target or parent: $ancestor" >&2; exit 1
      fi
      [[ "$ancestor" == "$HOME" || "$ancestor" == "$CACHE_ROOT" ]] && break
      ancestor="$(dirname "$ancestor")"
    done
  fi
  selected+=("$path")
  printf '[%s] %s\n' "${names[i]}" "$path"
  du -sh "$path" 2>/dev/null || true
done
if [[ ${#selected[@]} -eq 0 ]]; then echo "Nothing to clean."; exit 0; fi
if "$DRY_RUN"; then
  echo "[dry-run] No changes made. Use --execute with --all or --target NAME."
else
  for path in "${selected[@]}"; do
    echo "Removing: $path"
    rm -rf -- "$path"
  done
  echo "Done."
  df -h "$HOME"
fi
