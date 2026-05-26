#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$HOME/Developer/personal}"
FORMAT="${FORMAT:-table}"
SHOW_ALL=false
DRY_RUN=false
EXECUTE=false
LINE_REVIEW_THRESHOLD="${LINE_REVIEW_THRESHOLD:-60}"
LINE_BLOATED_THRESHOLD="${LINE_BLOATED_THRESHOLD:-150}"
WORD_REVIEW_THRESHOLD="${WORD_REVIEW_THRESHOLD:-1000}"
WORD_BLOATED_THRESHOLD="${WORD_BLOATED_THRESHOLD:-2500}"
GUIDE_NAMES=("AGENTS.md" "CLAUDE.md" "GEMINI.md")
TMP_DIR=""

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit-harness-guides.sh [options] [--dry-run|--execute]

Read-only audit for repo-local harness guide files such as AGENTS.md,
CLAUDE.md, and GEMINI.md. The default scans one directory level under
~/Developer/personal and reports guide size, repo-local skill references,
and likely review states.

Options:
      --all                       Show ok rows too
      --dry-run                   Show what would be audited without running it
      --execute                   Run the audit
  -f, --format <format>           Output format: table or tsv (default: table)
  -h, --help                      Show this help message
      --line-review-threshold <n> Review guide files above this line count
      --line-bloated-threshold <n>
                                   Mark guide files above this line count bloated
      --word-review-threshold <n> Review guide files above this word count
      --word-bloated-threshold <n>
                                   Mark guide files above this word count bloated
  -r, --root <path>               Directory containing local repo directories
      --shell-entrypoint-descriptor
                                   Print machine-readable entrypoint metadata

Examples:
  scripts/audit-harness-guides.sh --dry-run
  scripts/audit-harness-guides.sh --execute
  scripts/audit-harness-guides.sh --execute --root ~/Developer/work
  scripts/audit-harness-guides.sh --execute --all --format tsv
  scripts/audit-harness-guides.sh --execute --line-review-threshold 40
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

print_entrypoint_descriptor() {
  printf '{"schema_version":"shell-entrypoint/v1","name":"audit-harness-guides.sh","path":"%s","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}\n' "$0"
}

print_preview() {
  printf 'INFO dry-run: would scan one directory level under %s\n' "$ROOT_DIR"
  printf 'INFO dry-run: would inspect guide files: %s\n' "${GUIDE_NAMES[*]}"
  printf 'INFO dry-run: would count lines, words, and bytes for each guide\n'
  printf 'INFO dry-run: would report repo-local skill references in guide files\n'
  printf 'INFO dry-run: output format: %s\n' "$FORMAT"
  printf 'INFO dry-run: include ok rows: %s\n' "$SHOW_ALL"
}

parse_positive_int() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -eq 0 ]]; then
    error "$name requires a positive integer"
    usage 1
  fi
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
      --line-review-threshold)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          LINE_REVIEW_THRESHOLD="$2"
          shift 2
        else
          error "--line-review-threshold requires a value"
          usage 1
        fi
        ;;
      --line-review-threshold=*)
        LINE_REVIEW_THRESHOLD="${1#*=}"
        shift
        ;;
      --line-bloated-threshold)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          LINE_BLOATED_THRESHOLD="$2"
          shift 2
        else
          error "--line-bloated-threshold requires a value"
          usage 1
        fi
        ;;
      --line-bloated-threshold=*)
        LINE_BLOATED_THRESHOLD="${1#*=}"
        shift
        ;;
      --word-review-threshold)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          WORD_REVIEW_THRESHOLD="$2"
          shift 2
        else
          error "--word-review-threshold requires a value"
          usage 1
        fi
        ;;
      --word-review-threshold=*)
        WORD_REVIEW_THRESHOLD="${1#*=}"
        shift
        ;;
      --word-bloated-threshold)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          WORD_BLOATED_THRESHOLD="$2"
          shift 2
        else
          error "--word-bloated-threshold requires a value"
          usage 1
        fi
        ;;
      --word-bloated-threshold=*)
        WORD_BLOATED_THRESHOLD="${1#*=}"
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

  parse_positive_int "--line-review-threshold" "$LINE_REVIEW_THRESHOLD"
  parse_positive_int "--line-bloated-threshold" "$LINE_BLOATED_THRESHOLD"
  parse_positive_int "--word-review-threshold" "$WORD_REVIEW_THRESHOLD"
  parse_positive_int "--word-bloated-threshold" "$WORD_BLOATED_THRESHOLD"
}

count_lines() {
  local file="$1"

  wc -l <"$file" | tr -d ' '
}

count_words() {
  local file="$1"

  wc -w <"$file" | tr -d ' '
}

count_bytes() {
  local file="$1"

  wc -c <"$file" | tr -d ' '
}

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

join_by_comma() {
  local first=true
  local item

  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      printf '%s' "$item"
      first=false
    else
      printf ',%s' "$item"
    fi
  done
}

guide_files_for_repo() {
  local dir="$1"
  local name

  for name in "${GUIDE_NAMES[@]}"; do
    if [[ -f "$dir/$name" ]]; then
      printf '%s\n' "$name"
    fi
  done
}

repo_skill_count() {
  local dir="$1"

  if [[ ! -d "$dir/skills" ]]; then
    printf '0\n'
    return 0
  fi

  find "$dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' '
}

skill_refs_for_guides() {
  local dir="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  grep -Eho 'skills/[A-Za-z0-9._/-]+' "$@" 2>/dev/null \
    | sed 's#[).,;:]*$##' \
    | sort -u \
    | while IFS= read -r ref; do
        if [[ -n "$ref" ]]; then
          printf '%s\n' "$ref"
        fi
      done || true
}

missing_skill_ref_count() {
  local dir="$1"
  local refs_file="$2"
  local count=0
  local ref

  while IFS= read -r ref; do
    if [[ -z "$ref" ]]; then
      continue
    fi

    if [[ ! -e "$dir/$ref" ]]; then
      count=$((count + 1))
    fi
  done <"$refs_file"

  printf '%s\n' "$count"
}

scan_repo() {
  local dir="$1"
  local rows_file="$2"
  local name guides guide_paths refs_file guide_count largest_guide largest_lines largest_words largest_bytes
  local total_words total_lines guide skill_ref_count missing_ref_count skills_count state notes

  name="$(basename "$dir")"
  mapfile -t guides < <(guide_files_for_repo "$dir")
  guide_count="${#guides[@]}"
  skills_count="$(repo_skill_count "$dir")"
  largest_guide="-"
  largest_lines=0
  largest_words=0
  largest_bytes=0
  total_words=0
  total_lines=0

  guide_paths=()
  for guide in "${guides[@]}"; do
    local path lines words bytes
    path="$dir/$guide"
    lines="$(count_lines "$path")"
    words="$(count_words "$path")"
    bytes="$(count_bytes "$path")"
    total_lines=$((total_lines + lines))
    total_words=$((total_words + words))
    guide_paths+=("$path")

    if [[ "$lines" -gt "$largest_lines" || "$words" -gt "$largest_words" ]]; then
      largest_guide="$guide"
      largest_lines="$lines"
      largest_words="$words"
      largest_bytes="$bytes"
    fi
  done

  refs_file="$TMP_DIR/$name.refs"
  : >"$refs_file"
  if [[ "${#guide_paths[@]}" -gt 0 ]]; then
    skill_refs_for_guides "$dir" "${guide_paths[@]}" >"$refs_file"
  fi

  skill_ref_count="$(count_lines "$refs_file")"
  missing_ref_count="$(missing_skill_ref_count "$dir" "$refs_file")"
  state="ok"
  notes="-"

  if [[ "$missing_ref_count" -gt 0 ]]; then
    state="missing-skill-ref"
  elif [[ "$largest_lines" -gt "$LINE_BLOATED_THRESHOLD" || "$largest_words" -gt "$WORD_BLOATED_THRESHOLD" ]]; then
    state="bloated-guide"
  elif [[ "$largest_lines" -gt "$LINE_REVIEW_THRESHOLD" || "$largest_words" -gt "$WORD_REVIEW_THRESHOLD" ]]; then
    state="review-guide"
  elif [[ "$skills_count" -gt 0 && "$skill_ref_count" -eq 0 ]]; then
    state="repo-skills-unreferenced"
  elif [[ "$guide_count" -eq 0 ]]; then
    state="no-guide"
  fi

  if [[ "$guide_count" -gt 0 ]]; then
    notes="$(join_by_comma "${guides[@]}")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$guide_count" "$largest_guide" "$largest_lines" "$largest_words" "$largest_bytes" \
    "$skills_count" "$skill_ref_count" "$missing_ref_count" "$state" "$notes" "$dir" >>"$rows_file"
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
  local total_count guide_count no_guide_count review_count bloated_count missing_count unreferenced_count

  total_count="$(count_lines "$rows_file")"
  guide_count="$(awk -F $'\t' '$2 > 0 {c++} END {print c+0}' "$rows_file")"
  no_guide_count="$(awk -F $'\t' '$10 == "no-guide" {c++} END {print c+0}' "$rows_file")"
  review_count="$(awk -F $'\t' '$10 == "review-guide" {c++} END {print c+0}' "$rows_file")"
  bloated_count="$(awk -F $'\t' '$10 == "bloated-guide" {c++} END {print c+0}' "$rows_file")"
  missing_count="$(awk -F $'\t' '$10 == "missing-skill-ref" {c++} END {print c+0}' "$rows_file")"
  unreferenced_count="$(awk -F $'\t' '$10 == "repo-skills-unreferenced" {c++} END {print c+0}' "$rows_file")"

  printf 'Local root:       %s\n' "$ROOT_DIR"
  printf 'Guide files:      %s\n' "${GUIDE_NAMES[*]}"
  printf 'Review threshold: %s lines or %s words\n' "$LINE_REVIEW_THRESHOLD" "$WORD_REVIEW_THRESHOLD"
  printf 'Bloated threshold:%s lines or %s words\n' "$LINE_BLOATED_THRESHOLD" "$WORD_BLOATED_THRESHOLD"
  printf '\n'
  printf '%-26s %s\n' "Directories scanned" "$total_count"
  printf '%-26s %s\n' "Repos with guides" "$guide_count"
  printf '%-26s %s\n' "No guide" "$no_guide_count"
  printf '%-26s %s\n' "Review guide" "$review_count"
  printf '%-26s %s\n' "Bloated guide" "$bloated_count"
  printf '%-26s %s\n' "Missing skill refs" "$missing_count"
  printf '%-26s %s\n' "Unreferenced repo skills" "$unreferenced_count"

  if [[ "$SHOW_ALL" == "true" ]]; then
    sort -t $'\t' -k1,1 "$rows_file" >"$attention_file"
  else
    awk -F $'\t' '$10 != "ok" && $10 != "no-guide"' "$rows_file" | sort -t $'\t' -k1,1 >"$attention_file"
  fi

  if [[ -s "$attention_file" ]]; then
    printf '\nHarness guides needing attention\n'
    awk -F $'\t' '
      BEGIN {
        printf "%-34s %6s %-14s %7s %7s %7s %6s %6s %6s %-24s %s\n", "LOCAL", "GUIDES", "LARGEST", "LINES", "WORDS", "BYTES", "SKILLS", "REFS", "MISS", "STATE", "PATH"
      }
      {
        printf "%-34s %6s %-14s %7s %7s %7s %6s %6s %6s %-24s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $12
      }
    ' "$attention_file"
  fi
}

emit_tsv() {
  local rows_file="$1"

  printf '# summary\n'
  printf 'metric\tvalue\n'
  printf 'local_root\t%s\n' "$ROOT_DIR"
  printf 'guide_files\t%s\n' "${GUIDE_NAMES[*]}"
  printf 'line_review_threshold\t%s\n' "$LINE_REVIEW_THRESHOLD"
  printf 'line_bloated_threshold\t%s\n' "$LINE_BLOATED_THRESHOLD"
  printf 'word_review_threshold\t%s\n' "$WORD_REVIEW_THRESHOLD"
  printf 'word_bloated_threshold\t%s\n' "$WORD_BLOATED_THRESHOLD"
  printf 'directories_scanned\t%s\n' "$(count_lines "$rows_file")"
  printf 'repos_with_guides\t%s\n' "$(awk -F $'\t' '$2 > 0 {c++} END {print c+0}' "$rows_file")"

  printf '# repos\n'
  printf 'local\tguide_count\tlargest_guide\tlargest_lines\tlargest_words\tlargest_bytes\trepo_skill_count\tskill_ref_count\tmissing_skill_ref_count\tstate\tguides\tpath\n'
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

  if [[ ! -d "$ROOT_DIR" ]]; then
    error "Root directory not found: $ROOT_DIR"
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT
  rows_file="$TMP_DIR/harness-guides.tsv"
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
