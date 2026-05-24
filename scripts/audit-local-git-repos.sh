#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$HOME/Developer/personal}"
FORMAT="${FORMAT:-table}"
SHOW_ALL=false
DRY_RUN=false
EXECUTE=false
FETCH=false
MAIN_REF="${MAIN_REF:-origin/main}"
FALLBACK_MAIN_REF="${FALLBACK_MAIN_REF:-main}"
TMP_DIR=""

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit-local-git-repos.sh [options] [--dry-run|--execute]

Fast local-only audit for directories that should each be Git repositories.
The default scans one level under ~/Developer/personal, avoids network access,
and reports non-git directories plus repos not cleanly on main.

Options:
      --all                    Show clean repo rows too
      --dry-run                Show what would be audited without running it
      --execute                Run the audit
      --fetch                  Fetch origin before status checks
  -f, --format <format>        Output format: table or tsv (default: table)
  -h, --help                   Show this help message
      --main-ref <ref>         Main ref for drift checks (default: origin/main)
      --no-fetch               Use cached refs only (default)
  -r, --root <path>            Directory containing local repo directories
      --shell-entrypoint-descriptor
                                Print machine-readable entrypoint metadata

Examples:
  scripts/audit-local-git-repos.sh --dry-run
  scripts/audit-local-git-repos.sh --execute
  scripts/audit-local-git-repos.sh --execute --root ~/Developer/work
  scripts/audit-local-git-repos.sh --execute --all --format tsv
  scripts/audit-local-git-repos.sh --execute --fetch
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command not found: $1"
    exit 1
  fi
}

print_entrypoint_descriptor() {
  printf '{"schema_version":"shell-entrypoint/v1","name":"audit-local-git-repos.sh","path":"%s","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}\n' "$0"
}

print_preview() {
  printf 'INFO dry-run: would scan one directory level under %s\n' "$ROOT_DIR"
  printf 'INFO dry-run: would require each child directory to be a Git repo\n'
  printf 'INFO dry-run: would compare each repo HEAD with %s, falling back to %s\n' "$MAIN_REF" "$FALLBACK_MAIN_REF"
  printf 'INFO dry-run: would fetch origin before checks: %s\n' "$FETCH"
  printf 'INFO dry-run: output format: %s\n' "$FORMAT"
  printf 'INFO dry-run: include clean repo rows: %s\n' "$SHOW_ALL"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        SHOW_ALL=true
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
      --fetch)
        FETCH=true
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
      --main-ref)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          MAIN_REF="$2"
          shift 2
        else
          error "--main-ref requires a ref"
          usage 1
        fi
        ;;
      --main-ref=*)
        MAIN_REF="${1#*=}"
        shift
        ;;
      --no-fetch)
        FETCH=false
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
    table|tsv) ;;
    *)
      error "Unsupported format: $FORMAT"
      usage 1
      ;;
  esac
}

count_lines() {
  local file="$1"

  wc -l <"$file" | tr -d ' '
}

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

repo_main_ref() {
  local dir="$1"

  if git -C "$dir" rev-parse --verify --quiet "$MAIN_REF" >/dev/null; then
    printf '%s\n' "$MAIN_REF"
  elif git -C "$dir" rev-parse --verify --quiet "$FALLBACK_MAIN_REF" >/dev/null; then
    printf '%s\n' "$FALLBACK_MAIN_REF"
  else
    printf '%s\n' ""
  fi
}

scan_repo() {
  local dir="$1"
  local rows_file="$2"
  local name branch dirty_count fetch_state main_ref counts main_ahead main_behind main_state state top_level

  name="$(basename "$dir")"

  if ! top_level="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [[ "$top_level" != "$dir" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "no" "-" "-" "-" "-" "-" "not-git" "$dir" >>"$rows_file"
    return 0
  fi

  fetch_state="skipped"
  if [[ "$FETCH" == "true" ]]; then
    if git -C "$dir" fetch --prune --quiet origin 2>/dev/null; then
      fetch_state="ok"
    else
      fetch_state="failed"
    fi
  fi

  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'DETACHED')"
  dirty_count="$(git -C "$dir" status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')"
  main_ref="$(repo_main_ref "$dir")"
  main_ahead="-"
  main_behind="-"
  main_state="no-main-ref"

  if [[ -n "$main_ref" ]]; then
    counts="$(git -C "$dir" rev-list --left-right --count HEAD..."$main_ref" 2>/dev/null || true)"
    if [[ -n "$counts" ]]; then
      read -r main_ahead main_behind <<<"$counts"
    else
      main_ahead="0"
      main_behind="0"
    fi

    if [[ "$branch" == "main" && "$main_ahead" -eq 0 && "$main_behind" -eq 0 ]]; then
      main_state="on-main"
    elif [[ "$branch" == "main" && "$main_ahead" -gt 0 ]]; then
      main_state="main-ahead"
    elif [[ "$branch" == "main" && "$main_behind" -gt 0 ]]; then
      main_state="main-behind"
    elif [[ "$main_ahead" -gt 0 && "$main_behind" -gt 0 ]]; then
      main_state="branch-diverged-main"
    elif [[ "$main_ahead" -gt 0 ]]; then
      main_state="branch-ahead-main"
    elif [[ "$main_behind" -gt 0 ]]; then
      main_state="branch-behind-main"
    else
      main_state="branch-at-main"
    fi
  fi

  state="$main_state"
  if [[ "$dirty_count" -gt 0 ]]; then
    state="dirty+$state"
  fi
  if [[ "$fetch_state" == "failed" ]]; then
    state="fetch-failed+$state"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "yes" "$branch" "${main_ref:-"-"}" "$main_ahead" "$main_behind" "$dirty_count" "$state" "$dir" >>"$rows_file"
}

scan_root() {
  local rows_file="$1"
  local dir

  : >"$rows_file"

  while IFS= read -r -d '' dir; do
    scan_repo "$dir" "$rows_file"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

emit_table() {
  local rows_file="$1"
  local attention_file="$2"
  local total_count git_count non_git_count dirty_count not_main_count no_main_count fetch_failed_count

  total_count="$(count_lines "$rows_file")"
  git_count="$(awk -F $'\t' '$2 == "yes" {c++} END {print c+0}' "$rows_file")"
  non_git_count="$(awk -F $'\t' '$2 == "no" {c++} END {print c+0}' "$rows_file")"
  dirty_count="$(awk -F $'\t' '$7 > 0 {c++} END {print c+0}' "$rows_file")"
  not_main_count="$(awk -F $'\t' '$8 != "on-main" && $8 != "dirty+on-main" && $2 == "yes" {c++} END {print c+0}' "$rows_file")"
  no_main_count="$(awk -F $'\t' '$8 ~ /no-main-ref/ {c++} END {print c+0}' "$rows_file")"
  fetch_failed_count="$(awk -F $'\t' '$8 ~ /fetch-failed/ {c++} END {print c+0}' "$rows_file")"

  printf 'Local root:   %s\n' "$ROOT_DIR"
  printf 'Main ref:     %s\n' "$MAIN_REF"
  printf 'Fetch:        %s\n' "$FETCH"
  printf '\n'
  printf '%-22s %s\n' "Directories scanned" "$total_count"
  printf '%-22s %s\n' "Git repos" "$git_count"
  printf '%-22s %s\n' "Non-git directories" "$non_git_count"
  printf '%-22s %s\n' "Dirty worktrees" "$dirty_count"
  printf '%-22s %s\n' "Not cleanly on main" "$not_main_count"
  printf '%-22s %s\n' "No main ref" "$no_main_count"
  printf '%-22s %s\n' "Fetch failures" "$fetch_failed_count"

  if [[ "$SHOW_ALL" == "true" ]]; then
    sort -t $'\t' -k1,1 "$rows_file" >"$attention_file"
  else
    awk -F $'\t' '$2 == "no" || $7 > 0 || $8 != "on-main"' "$rows_file" | sort -t $'\t' -k1,1 >"$attention_file"
  fi

  if [[ -s "$attention_file" ]]; then
    printf '\nRepos needing attention\n'
    awk -F $'\t' '
      BEGIN {
        printf "%-34s %-5s %-28s %-16s %6s %6s %5s %-28s %s\n", "LOCAL", "GIT", "BRANCH", "MAIN_REF", "MAIN+", "MAIN-", "DIRTY", "STATE", "PATH"
      }
      {
        printf "%-34s %-5s %-28s %-16s %6s %6s %5s %-28s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9
      }
    ' "$attention_file"
  fi
}

emit_tsv() {
  local rows_file="$1"

  printf '# summary\n'
  printf 'metric\tvalue\n'
  printf 'local_root\t%s\n' "$ROOT_DIR"
  printf 'main_ref\t%s\n' "$MAIN_REF"
  printf 'fetch\t%s\n' "$FETCH"
  printf 'directories_scanned\t%s\n' "$(count_lines "$rows_file")"
  printf 'git_repos\t%s\n' "$(awk -F $'\t' '$2 == "yes" {c++} END {print c+0}' "$rows_file")"
  printf 'non_git_directories\t%s\n' "$(awk -F $'\t' '$2 == "no" {c++} END {print c+0}' "$rows_file")"

  printf '# repos\n'
  printf 'local\tis_git\tbranch\tmain_ref\tmain_ahead\tmain_behind\tdirty_count\tstate\tpath\n'
  sort -t $'\t' -k1,1 "$rows_file"
}

main() {
  local rows_file attention_file

  parse_args "$@"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_preview
    exit 0
  fi

  if [[ "$EXECUTE" != "true" ]]; then
    usage 0
  fi

  require_command git

  if [[ ! -d "$ROOT_DIR" ]]; then
    error "Root directory not found: $ROOT_DIR"
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT
  rows_file="$TMP_DIR/repos.tsv"
  attention_file="$TMP_DIR/attention.tsv"

  scan_root "$rows_file"

  case "$FORMAT" in
    table)
      emit_table "$rows_file" "$attention_file"
      ;;
    tsv)
      emit_tsv "$rows_file"
      ;;
  esac
}

main "$@"
