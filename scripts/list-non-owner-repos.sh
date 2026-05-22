#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$HOME/Developer/personal}"
TARGET_OWNER="${TARGET_OWNER:-nickromney}"
FORMAT="${FORMAT:-table}"
INCLUDE_OWNED=false
DRY_RUN=false
EXECUTE=false
RESULTS_FILE=""

print_usage() {
  cat <<'EOF'
Usage: scripts/list-non-owner-repos.sh [options] [--dry-run|--execute]

List Git repositories under a directory whose origin remote is not owned by a
target GitHub owner. The default checks ~/Developer/personal against nickromney.
Without --execute, this script prints a preview and exits before scanning repos.

Options:
      --all              Include matching owner repos in the output
      --dry-run          Show what would be audited without running it
      --execute          Run the audit
  -f, --format <format>  Output format: table, tsv, paths (default: table)
  -h, --help             Show this help message
  -o, --owner <owner>    Target GitHub owner to treat as expected
  -r, --root <path>      Directory containing local repos
      --shell-entrypoint-descriptor
                          Print machine-readable entrypoint metadata

Examples:
  scripts/list-non-owner-repos.sh --dry-run
  scripts/list-non-owner-repos.sh --execute
  scripts/list-non-owner-repos.sh --execute --root ~/Developer/work --owner RNLI-Workspace
  scripts/list-non-owner-repos.sh --execute --format paths
EOF
}

usage() {
  local exit_code=${1:-0}

  print_usage

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

print_entrypoint_descriptor() {
  printf '{"schema_version":"shell-entrypoint/v1","name":"list-non-owner-repos.sh","path":"%s","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}\n' "$0"
}

print_preview() {
  printf 'INFO dry-run: would scan top-level Git repos under %s\n' "$ROOT_DIR"
  printf 'INFO dry-run: would treat GitHub owner %s as expected\n' "$TARGET_OWNER"
  printf 'INFO dry-run: would include owned repos: %s\n' "$INCLUDE_OWNED"
  printf 'INFO dry-run: output format: %s\n' "$FORMAT"
}

cleanup() {
  if [[ -n "$RESULTS_FILE" ]]; then
    rm -f "$RESULTS_FILE"
  fi
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

strip_github_suffix() {
  local value="$1"

  value="${value%/}"
  value="${value%.git}"
  printf '%s\n' "$value"
}

github_remote_owner_repo() {
  local url="$1"
  local host=""
  local path=""
  local owner=""
  local repo=""
  local rest=""

  case "$url" in
    git@*:*)
      host="${url#git@}"
      host="${host%%:*}"
      path="${url#*:}"
      ;;
    ssh://git@*/*)
      rest="${url#ssh://git@}"
      host="${rest%%/*}"
      path="${rest#"$host"/}"
      ;;
    https://*/*)
      rest="${url#https://}"
      host="${rest%%/*}"
      path="${rest#"$host"/}"
      ;;
    http://*/*)
      rest="${url#http://}"
      host="${rest%%/*}"
      path="${rest#"$host"/}"
      ;;
    git://*/*)
      rest="${url#git://}"
      host="${rest%%/*}"
      path="${rest#"$host"/}"
      ;;
    github.com/*)
      host="github.com"
      path="${url#github.com/}"
      ;;
    github.com:*)
      host="github.com"
      path="${url#github.com:}"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "$(lowercase "$host")" != "github.com" ]]; then
    return 1
  fi

  path="$(strip_github_suffix "$path")"
  IFS='/' read -r owner repo _ <<<"$path"

  if [[ -z "${owner:-}" || -z "${repo:-}" ]]; then
    return 1
  fi

  printf '%s\t%s\n' "$owner" "$repo"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        INCLUDE_OWNED=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --execute)
        EXECUTE=true
        shift
        ;;
      -f|--format)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          FORMAT="$2"
          shift 2
        else
          error "--format requires a value"
          usage 1
        fi
        ;;
      --format=*)
        FORMAT="${1#*=}"
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      -o|--owner)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          TARGET_OWNER="${2#@}"
          shift 2
        else
          error "--owner requires a GitHub owner"
          usage 1
        fi
        ;;
      --owner=*)
        TARGET_OWNER="${1#*=}"
        TARGET_OWNER="${TARGET_OWNER#@}"
        shift
        ;;
      -r|--root)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          ROOT_DIR="$2"
          shift 2
        else
          error "--root requires a directory path"
          usage 1
        fi
        ;;
      --root=*)
        ROOT_DIR="${1#*=}"
        shift
        ;;
      --shell-entrypoint-descriptor)
        print_entrypoint_descriptor
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage 1
        ;;
    esac
  done

  case "$FORMAT" in
    table|tsv|paths) ;;
    *)
      error "Unsupported format: $FORMAT"
      usage 1
      ;;
  esac
}

emit_results() {
  local results_file="$1"

  case "$FORMAT" in
    table)
      printf '%-16s %-38s %-42s %s\n' "STATUS" "LOCAL" "REMOTE" "ORIGIN"
      sort -t $'\t' -k2,2 "$results_file" |
        while IFS=$'\t' read -r status local_name remote origin path; do
          printf '%-16s %-38s %-42s %s\n' "$status" "$local_name" "$remote" "$origin"
        done
      ;;
    tsv)
      printf 'status\tlocal\tremote\torigin\tpath\n'
      sort -t $'\t' -k2,2 "$results_file"
      ;;
    paths)
      sort -t $'\t' -k2,2 "$results_file" |
        while IFS=$'\t' read -r _ _ _ _ path; do
          printf '%s\n' "$path"
        done
      ;;
  esac
}

main() {
  local repo_count=0
  local result_count=0
  local expected_owner

  parse_args "$@"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_preview
    exit 0
  fi

  if [[ "$EXECUTE" != "true" ]]; then
    print_usage
    printf '\n'
    print_preview
    exit 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    error "git is required"
    exit 1
  fi

  if [[ ! -d "$ROOT_DIR" ]]; then
    error "Root directory not found: $ROOT_DIR"
    exit 1
  fi

  expected_owner="$(lowercase "$TARGET_OWNER")"
  RESULTS_FILE="$(mktemp)"
  trap cleanup EXIT

  while IFS= read -r -d '' dir; do
    local top_level
    local local_name
    local origin
    local parsed
    local remote_owner
    local remote_repo
    local remote_label
    local status

    if ! top_level="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
      continue
    fi

    if [[ "$top_level" != "$dir" ]]; then
      continue
    fi

    repo_count=$((repo_count + 1))
    local_name="$(basename "$dir")"

    if ! origin="$(git -C "$dir" remote get-url origin 2>/dev/null)"; then
      status="missing-origin"
      remote_label="-"
    elif parsed="$(github_remote_owner_repo "$origin")"; then
      IFS=$'\t' read -r remote_owner remote_repo <<<"$parsed"
      remote_label="$remote_owner/$remote_repo"

      if [[ "$(lowercase "$remote_owner")" == "$expected_owner" ]]; then
        status="owned"
      else
        status="external-owner"
      fi
    else
      status="non-github-origin"
      remote_label="-"
    fi

    if [[ "$status" == "owned" && "$INCLUDE_OWNED" != "true" ]]; then
      continue
    fi

    result_count=$((result_count + 1))
    printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$local_name" "$remote_label" "${origin:-<no origin>}" "$dir" >>"$RESULTS_FILE"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  emit_results "$RESULTS_FILE"
  printf 'Found %s matching repos out of %s Git repos under %s.\n' "$result_count" "$repo_count" "$ROOT_DIR" >&2
}

main "$@"
