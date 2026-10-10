#!/usr/bin/env bash
# Delete explicitly selected Lima instances through Lima's lifecycle API.
set -euo pipefail

DRY_RUN=true
ALL=false
FORCE=false
INSTANCES=()

usage() {
  cat <<'HELP'
Usage: scripts/cleanup-lima.sh [options]

Preview all Lima instances and the image cache by default; no changes are made.
Execute permanently deletes selected VMs,
including their instance disks, snapshots and guest data. Host shared folders,
Lima configuration and separately managed additional disks are retained.
--all also clears downloaded Lima images, even if no instances remain:
  macOS: ~/Library/Caches/lima
  Linux: ${XDG_CACHE_HOME:-$HOME/.cache}/lima
Lima downloads needed images again when creating future VMs.
--instance keeps this shared cache. Cache cleanup runs after successful VM deletion.
Run as your login user, without sudo. LIMA_HOME is honored by limactl.

Options:
  -d, --dry-run       Preview only (default)
      --execute       Apply cleanup; requires --instance NAME or --all
      --instance NAME Select an instance (repeatable)
      --all           Select all current instances and clear the Lima cache
      --force         Force stop/delete broken or unresponsive instances
      --no-input      No prompts; --execute is explicit deletion consent
  -h, --help          Show this help

Examples:
  scripts/cleanup-lima.sh
  scripts/cleanup-lima.sh --dry-run --instance k3s-node-1
  scripts/cleanup-lima.sh --execute --no-input --instance k3s-node-1
  scripts/cleanup-lima.sh --dry-run --all
  scripts/cleanup-lima.sh --execute --all
HELP
}

for_mode=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute|-d|--dry-run)
      mode="$1"
      [[ "$mode" == -d ]] && mode=--dry-run
      if [[ -n "$for_mode" && "$for_mode" != "$mode" ]]; then
        echo "Cannot combine --execute and --dry-run" >&2
        exit 1
      fi
      for_mode="$mode"
      [[ "$mode" == --execute ]] && DRY_RUN=false
      shift
      ;;
    --instance)
      if [[ $# -lt 2 || ! "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        echo "--instance requires a Lima instance name" >&2
        exit 1
      fi
      INSTANCES+=("$2")
      shift 2
      ;;
    --all) ALL=true; shift ;;
    --force) FORCE=true; shift ;;
    --no-input) shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if "$ALL" && [[ ${#INSTANCES[@]} -gt 0 ]]; then
  echo "Use either --all or --instance, not both" >&2
  exit 1
fi
if ! "$DRY_RUN" && ! "$ALL" && [[ ${#INSTANCES[@]} -eq 0 ]]; then
  echo "--execute requires --instance NAME or --all" >&2
  exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your login user, without sudo" >&2
  exit 1
fi
if ! command -v limactl >/dev/null 2>&1; then
  echo "limactl is required to inspect and delete Lima instances" >&2
  exit 1
fi

# Capture first so a failed list cannot masquerade as an empty inventory.
inventory=$(limactl --tty=false list --format '{{.Name}} {{.Status}}') || {
  echo "Cannot list Lima instances; no cleanup performed" >&2
  exit 1
}
selected_names=()
selected_statuses=()
while read -r name status extra; do
  [[ -n "$name" ]] || continue
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || -z "$status" || -n "$extra" ]]; then
    echo "Unexpected Lima inventory; no cleanup performed" >&2
    exit 1
  fi
  select_instance=false
  if "$ALL" || [[ ${#INSTANCES[@]} -eq 0 ]]; then
    select_instance=true
  else
    for requested in "${INSTANCES[@]}"; do
      [[ "$requested" == "$name" ]] && select_instance=true
    done
  fi
  if "$select_instance"; then
    selected_names+=("$name")
    selected_statuses+=("$status")
  fi
done <<< "$inventory"

for requested in "${INSTANCES[@]+"${INSTANCES[@]}"}"; do
  exists=false
  for name in "${selected_names[@]+"${selected_names[@]}"}"; do
    [[ "$requested" == "$name" ]] && exists=true
  done
  "$exists" || echo "Already absent: $requested"
done
if [[ ${#selected_names[@]} -eq 0 ]]; then
  echo "Nothing to remove - no selected Lima instances found."
fi

cache_dir=""
if "$ALL" || [[ ${#INSTANCES[@]} -eq 0 ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    cache_dir="$HOME/Library/Caches/lima"
  else
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/lima"
  fi
  if [[ "$cache_dir" != /* ]]; then
    echo "Lima cache path must be absolute; no cleanup performed" >&2
    exit 1
  fi
  if [[ -e "$cache_dir" || -L "$cache_dir" ]]; then
    echo "  [cache] $cache_dir"
    du -sh "$cache_dir" 2>/dev/null || true
  fi
fi

# Validate every selected state before starting any destructive operation.
for ((i=0; i<${#selected_names[@]}; i++)); do
  name="${selected_names[i]}"
  status="${selected_statuses[i]}"
  echo "  [instance] $name ($status)"
  if ! "$DRY_RUN" && ! "$FORCE" && [[ "$status" != Running && "$status" != Stopped ]]; then
    echo "Refusing cleanup of $name in state $status; inspect it or explicitly use --force" >&2
    exit 1
  fi
done
flags=()
"$FORCE" && flags+=(--force)
for ((i=0; i<${#selected_names[@]}; i++)); do
  name="${selected_names[i]}"
  status="${selected_statuses[i]}"
  if "$DRY_RUN"; then
    echo "[dry-run] Would stop (if needed) and delete: $name"
    continue
  fi
  if [[ "$status" != Stopped ]]; then
    echo "Stopping: $name"
    limactl --tty=false stop "${flags[@]+"${flags[@]}"}" "$name" || {
      echo "Failed to stop $name; deletion aborted" >&2
      exit 1
    }
  fi
  echo "Deleting instance and its disks: $name"
  limactl --tty=false delete "${flags[@]+"${flags[@]}"}" "$name" || {
    echo "Failed to delete $name; cleanup aborted" >&2
    exit 1
  }
done
if [[ -n "$cache_dir" && ( -e "$cache_dir" || -L "$cache_dir" ) ]]; then
  if "$DRY_RUN"; then
    echo "[dry-run] Would clear Lima cache: $cache_dir"
  else
    echo "Clearing Lima cache: $cache_dir"
    rm -rf -- "$cache_dir"
  fi
fi
if "$DRY_RUN"; then
  echo "[dry-run] No changes made. Pass --execute with --instance NAME or --all to delete."
else
  echo "Done."
fi
