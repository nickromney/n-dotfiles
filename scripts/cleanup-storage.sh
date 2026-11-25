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
PROJECT_SCOPE=false
PROJECT_ARGS=()
DOCKER_VOLUMES=false
REMOVE_VOLUME_CONTAINERS=false
VERBOSE=false

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
      --execute       Apply an explicit cleanup selection
      --all           Clear the defined rebuildable cache set
      --target NAME   Select a catalog target (repeatable; see --list)
      --list          Show every target and its path; do not delete
      --report        Show sizes of major storage directories; do not delete
      --interactive   Show the chooser (also supports piped answers)
      --no-input      Disable chooser; --execute is explicit deletion consent
      --project-caches ROOT
                      Discover ignored project caches recursively (repeatable)
      --retire-checkouts ROOT
                      Archive and retire standalone checkouts (repeatable)
      --archive-root PATH
                      Recovery directory required by --retire-checkouts
      --verbose       List every project cache directory instead of a per-repo summary
      --docker-volumes
                      Report Docker volume usage and select unused local volumes
      --remove-volume-containers
                      Include attached volumes and remove their containers
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
  scripts/cleanup-storage.sh --project-caches ~/Developer/personal --dry-run
  scripts/cleanup-storage.sh --project-caches /path/to/review-workspace/implementation --execute --no-input
  scripts/cleanup-storage.sh --retire-checkouts /path/to/review-workspace/implementation --archive-root /path/to/recovery --dry-run
  scripts/cleanup-storage.sh --docker-volumes
  scripts/cleanup-storage.sh --docker-volumes --execute --no-input
  scripts/cleanup-storage.sh --docker-volumes --remove-volume-containers --dry-run

Project scopes need Python 3.9+ and Git. Close tools using selected projects.
Only ignored rebuildable caches are cleared. Tracked/nonignored untracked paths,
reports, evidence, Terraform backend metadata/state and nested Git stores stay.
Retirement preserves complete Git history, staged/unstaged/untracked files and
ignored noncache data in verified recovery archives before removing checkouts.
Linked worktrees and external Git object stores must be handled separately.
Project scopes are separate from --all, --target, --report and --list.
Docker volume cleanup uses the current Docker context and requires a local
Unix socket. Keep Docker workloads idle during cleanup. Attached volumes and
their containers require --remove-volume-containers. Execution permanently
deletes the selected volumes and the writable layers of any removed containers.
HELP
}

bounded_docker_read() {
  local seconds=$1 pid started
  shift
  if command -v timeout >/dev/null; then
    timeout -k 1 "$seconds" "$@"
    return
  fi
  if command -v gtimeout >/dev/null; then
    gtimeout -k 1 "$seconds" "$@"
    return
  fi

  "$@" </dev/null &
  pid=$!
  started=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - started >= seconds )); then
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
  done
  wait "$pid"
}

print_docker_volume_usage() {
  local summary status=0
  summary=$(bounded_docker_read 20 "$@" system df --format '{{if eq .Type "Local Volumes"}}Docker volumes: {{.Size}} total, {{.Reclaimable}} reclaimable{{end}}' |
    sed '/^$/d') || status=$?
  if (( status == 124 || status == 137 )); then
    printf 'Docker volume usage report timed out.\n' >&2
  elif (( status != 0 )) || [[ -z "$summary" ]]; then
    printf 'Docker volume usage report unavailable.\n' >&2
  else
    printf '%s\n' "$summary"
  fi
}

cleanup_docker_volumes() {
  local context endpoint volumes volume references container_id container_name
  local -a docker_cli selected=() containers=()
  command -v docker >/dev/null || { echo "Docker CLI is required" >&2; return 1; }
  context=$(docker context show)
  endpoint=$(docker context inspect "$context" --format '{{.Endpoints.docker.Host}}')
  if [[ "$endpoint" != unix:///* ]]; then
    printf 'Docker volume cleanup requires a local Unix socket. Check context %s.\n' "$context" >&2
    return 1
  fi

  docker_cli=(docker --host "$endpoint")
  printf 'Docker context: %s (%s)\n' "$context" "$endpoint"
  print_docker_volume_usage "${docker_cli[@]}"

  if ! volumes=$(bounded_docker_read 10 "${docker_cli[@]}" volume ls --quiet --filter driver=local); then
    printf 'Cannot list local Docker volumes. Check the Docker daemon and retry.\n' >&2
    return 1
  fi
  if [[ -z "$volumes" ]]; then
    printf 'No local Docker volumes found.\n'
    return
  fi

  while IFS= read -r volume; do
    if ! references=$(bounded_docker_read 10 "${docker_cli[@]}" container ls --all --no-trunc --filter "volume=$volume" --format '{{.ID}} {{.Names}}'); then
      printf 'Cannot check which containers use Docker volume %s. Check the Docker daemon and retry.\n' "$volume" >&2
      return 1
    fi
    if [[ -n "$references" ]] && ! "$REMOVE_VOLUME_CONTAINERS"; then
      printf 'Keep attached volume: %s\n' "$volume"
    else
      printf 'Remove volume: %s\n' "$volume"
      selected+=("$volume")
    fi
    while read -r container_id container_name; do
      [[ -n "$container_id" ]] || continue
      printf '  Referenced by container: %s\n' "$container_name"
      if "$REMOVE_VOLUME_CONTAINERS" && [[ " ${containers[*]-} " != *" $container_id "* ]]; then
        containers+=("$container_id")
      fi
    done <<< "$references"
  done <<< "$volumes"

  if "$DRY_RUN"; then
    printf '[dry-run] No changes made. Use --execute to apply this selection.\n'
    return
  fi
  if (( ${#containers[@]} )); then
    "${docker_cli[@]}" container rm --force -- "${containers[@]}"
  fi
  if (( ${#selected[@]} )); then
    "${docker_cli[@]}" volume rm -- "${selected[@]}"
    printf 'Docker volume usage after cleanup\n'
    print_docker_volume_usage "${docker_cli[@]}"
  fi
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
    --docker-volumes) DOCKER_VOLUMES=true; shift ;;
    --remove-volume-containers) REMOVE_VOLUME_CONTAINERS=true; shift ;;
    --project-caches|--retire-checkouts|--archive-root)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "$1 requires a path" >&2; exit 1
      fi
      PROJECT_SCOPE=true; PROJECT_ARGS+=("$1" "$2"); shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
if "$INTERACTIVE" && { "$NO_INPUT" || [[ -n "$MODE" ]] || "$ALL" || "$REPORT" || "$LIST" || "$PROJECT_SCOPE" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use --interactive on its own" >&2; exit 1
fi
if [[ $ARG_COUNT -eq 0 && -t 0 && -t 1 ]]; then INTERACTIVE=true; fi
if { "$REPORT" || "$LIST"; } && { ! "$DRY_RUN" || "$ALL" || "$PROJECT_SCOPE" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use --report or --list without cleanup selections or --execute" >&2; exit 1
fi
if "$REPORT" && "$LIST"; then
  echo "Use either --report or --list" >&2; exit 1
fi
if "$ALL" && [[ ${#TARGETS[@]} -gt 0 ]]; then
  echo "Use either --all or --target" >&2; exit 1
fi
if "$PROJECT_SCOPE" && { "$ALL" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use project scopes separately from --all or --target" >&2; exit 1
fi
if "$VERBOSE" && ! "$PROJECT_SCOPE"; then
  echo "--verbose is only used with --project-caches or --retire-checkouts" >&2; exit 1
fi
if "$REMOVE_VOLUME_CONTAINERS" && ! "$DOCKER_VOLUMES"; then
  echo "--remove-volume-containers requires --docker-volumes" >&2; exit 1
fi
if "$DOCKER_VOLUMES" && { "$INTERACTIVE" || "$REPORT" || "$LIST" || "$ALL" || "$PROJECT_SCOPE" || [[ ${#TARGETS[@]} -gt 0 ]]; }; then
  echo "Use --docker-volumes separately from other storage modes" >&2; exit 1
fi
if ! "$DRY_RUN" && ! "$ALL" && ! "$PROJECT_SCOPE" && ! "$DOCKER_VOLUMES" && [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "--execute requires --all, --target NAME, --docker-volumes or an explicit project scope" >&2; exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your login user, without sudo" >&2; exit 1
fi
if "$DOCKER_VOLUMES"; then
  cleanup_docker_volumes
  exit 0
fi
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ "$HOME" != /* || "$HOME" == / || "$CACHE_ROOT" != /* || "$CACHE_ROOT" == / ]]; then
  echo "HOME and XDG_CACHE_HOME must be absolute, non-root directories" >&2; exit 1
fi
if "$PROJECT_SCOPE"; then
  command -v python3 >/dev/null 2>&1 || { echo "Project cleanup requires Python 3.9+" >&2; exit 1; }
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! "$DRY_RUN"; then PROJECT_ARGS+=(--execute); fi
  if "$VERBOSE"; then PROJECT_ARGS+=(--verbose); fi
  exec python3 "$script_dir/cleanup_storage_projects.py" "${PROJECT_ARGS[@]}"
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
