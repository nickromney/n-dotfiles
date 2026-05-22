#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$HOME/Developer/personal}"
OWNER="${GITHUB_OWNER:-nickromney}"
LIMIT="${GITHUB_REPO_LIMIT:-1000}"
FORMAT="${FORMAT:-table}"
FETCH=true
SHOW_ALL=false
DRY_RUN=false
EXECUTE=false
CACHE_TTL_HOURS="${GITHUB_REPO_CACHE_TTL_HOURS:-24}"
CACHE_DIR="${GITHUB_REPO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/n-dotfiles}"
CACHE_FILE="${GITHUB_REPO_CACHE_FILE:-}"
REFRESH_CACHE=false
EXCLUDE_ARCHIVED=false
EXCLUDE_FORKS=false
EXCLUDE_REPOS=()
EXCLUDE_FILES=()
TMP_DIR=""

print_usage() {
  cat <<'EOF'
Usage: scripts/audit-github-repos.sh [options] [--dry-run|--execute]

Compare a GitHub owner's repositories with local clones, then report upstream
status and branch drift from origin/main. The default checks nickromney repos
under ~/Developer/personal and fetches remotes before computing status. Without
--execute, this script prints a preview and exits before querying GitHub or Git.

Options:
      --all                    Show clean repo status rows too
      --cache-file <path>      GitHub repo-list cache file
      --cache-ttl-hours <n>    Reuse GitHub repo cache for n hours (default: 24)
      --dry-run                Show what would be audited without running it
      --execute                Run the audit
      --exclude <repo>         Exclude a repo name or owner/repo (repeatable)
      --exclude-archived       Exclude archived GitHub repos from expected clones
      --exclude-file <path>    Exclude repos listed in a file, one per line
      --exclude-forks          Exclude forked GitHub repos from expected clones
  -f, --format <format>        Output format: table or tsv (default: table)
      --fetch                  Fetch remotes before status checks (default)
  -h, --help                   Show this help message
      --limit <n>              Max GitHub repos to query (default: 1000)
      --no-fetch               Use cached remote refs; do not fetch
  -o, --owner <owner>          GitHub owner to audit (default: nickromney)
      --refresh-cache          Ignore cached GitHub repo list and query gh
  -r, --root <path>            Directory containing local clones
      --shell-entrypoint-descriptor
                                Print machine-readable entrypoint metadata

Examples:
  scripts/audit-github-repos.sh --dry-run
  scripts/audit-github-repos.sh --execute
  scripts/audit-github-repos.sh --execute --no-fetch
  scripts/audit-github-repos.sh --execute --refresh-cache
  scripts/audit-github-repos.sh --execute --exclude-file ~/.config/repo-audit/excludes.txt
  scripts/audit-github-repos.sh --execute --owner nickromney --root ~/Developer/personal --format tsv
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

log_info() {
  printf 'INFO %s\n' "$*" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command not found: $1"
    exit 1
  fi
}

print_entrypoint_descriptor() {
  printf '{"schema_version":"shell-entrypoint/v1","name":"audit-github-repos.sh","path":"%s","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}\n' "$0"
}

print_preview() {
  printf 'INFO dry-run: would audit GitHub owner %s against local root %s\n' "$OWNER" "$ROOT_DIR"
  printf 'INFO dry-run: would query up to %s GitHub repos with gh if cache is stale\n' "$LIMIT"
  printf 'INFO dry-run: would reuse GitHub repo cache for %s hour(s)\n' "$CACHE_TTL_HOURS"
  printf 'INFO dry-run: would refresh cache regardless of age: %s\n' "$REFRESH_CACHE"
  printf 'INFO dry-run: would scan local top-level Git repos and compute origin/main drift\n'
  printf 'INFO dry-run: would fetch origin before status checks: %s\n' "$FETCH"
  printf 'INFO dry-run: output format: %s\n' "$FORMAT"
  printf 'INFO dry-run: include clean status rows: %s\n' "$SHOW_ALL"
  printf 'INFO dry-run: exclude archived repos: %s\n' "$EXCLUDE_ARCHIVED"
  printf 'INFO dry-run: exclude forked repos: %s\n' "$EXCLUDE_FORKS"
  printf 'INFO dry-run: explicit excludes: %s\n' "${#EXCLUDE_REPOS[@]}"
  printf 'INFO dry-run: exclude files: %s\n' "${#EXCLUDE_FILES[@]}"
}

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

sanitize_cache_key() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

cache_file_path() {
  local owner_key

  if [[ -n "$CACHE_FILE" ]]; then
    printf '%s\n' "$CACHE_FILE"
    return 0
  fi

  owner_key="$(sanitize_cache_key "$OWNER")"
  printf '%s/github-repos-%s-limit-%s.json\n' "$CACHE_DIR" "$owner_key" "$LIMIT"
}

file_mtime_epoch() {
  local file="$1"

  case "$(uname -s)" in
    Darwin|FreeBSD|OpenBSD|NetBSD)
      stat -f %m "$file"
      ;;
    *)
      stat -c %Y "$file"
      ;;
  esac
}

cache_is_fresh() {
  local file="$1"
  local now
  local mtime
  local age
  local ttl_seconds

  [[ -s "$file" ]] || return 1
  [[ "$REFRESH_CACHE" == "false" ]] || return 1

  ttl_seconds=$((CACHE_TTL_HOURS * 3600))
  if [[ "$ttl_seconds" -eq 0 ]]; then
    return 1
  fi

  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$file")"
  age=$((now - mtime))

  [[ "$age" -lt "$ttl_seconds" ]]
}

strip_spaces() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

normalize_repo_key() {
  local value

  value="$(strip_spaces "$1")"
  value="${value#@}"

  if [[ -z "$value" ]]; then
    return 1
  fi

  if [[ "$value" == */* ]]; then
    lowercase "$value"
  else
    lowercase "$OWNER/$value"
  fi
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

  printf '%s/%s\n' "$owner" "$repo"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        SHOW_ALL=true
        shift
        ;;
      --cache-file)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          CACHE_FILE="$2"
          shift 2
        else
          error "--cache-file requires a path"
          usage 1
        fi
        ;;
      --cache-file=*)
        CACHE_FILE="${1#*=}"
        shift
        ;;
      --cache-ttl-hours)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          CACHE_TTL_HOURS="$2"
          shift 2
        else
          error "--cache-ttl-hours requires a number"
          usage 1
        fi
        ;;
      --cache-ttl-hours=*)
        CACHE_TTL_HOURS="${1#*=}"
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
      --exclude)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          EXCLUDE_REPOS+=("$2")
          shift 2
        else
          error "--exclude requires a repo name or owner/repo"
          usage 1
        fi
        ;;
      --exclude=*)
        EXCLUDE_REPOS+=("${1#*=}")
        shift
        ;;
      --exclude-archived)
        EXCLUDE_ARCHIVED=true
        shift
        ;;
      --exclude-file)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          EXCLUDE_FILES+=("$2")
          shift 2
        else
          error "--exclude-file requires a path"
          usage 1
        fi
        ;;
      --exclude-file=*)
        EXCLUDE_FILES+=("${1#*=}")
        shift
        ;;
      --exclude-forks)
        EXCLUDE_FORKS=true
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
      --fetch)
        FETCH=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      --limit)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          LIMIT="$2"
          shift 2
        else
          error "--limit requires a number"
          usage 1
        fi
        ;;
      --limit=*)
        LIMIT="${1#*=}"
        shift
        ;;
      --no-fetch)
        FETCH=false
        shift
        ;;
      -o|--owner)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          OWNER="${2#@}"
          shift 2
        else
          error "--owner requires a GitHub owner"
          usage 1
        fi
        ;;
      --owner=*)
        OWNER="${1#*=}"
        OWNER="${OWNER#@}"
        shift
        ;;
      --refresh-cache)
        REFRESH_CACHE=true
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

  if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -lt 1 ]]; then
    error "--limit must be a positive integer"
    usage 1
  fi

  if ! [[ "$CACHE_TTL_HOURS" =~ ^[0-9]+$ ]]; then
    error "--cache-ttl-hours must be a non-negative integer"
    usage 1
  fi
}

write_excludes() {
  local excludes_file="$1"
  local exclude
  local file
  local line
  local key

  : >"$excludes_file"

  for exclude in "${EXCLUDE_REPOS[@]}"; do
    if key="$(normalize_repo_key "$exclude")"; then
      printf '%s\n' "$key" >>"$excludes_file"
    fi
  done

  for file in "${EXCLUDE_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
      error "Exclude file not found: $file"
      exit 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      if key="$(normalize_repo_key "$line")"; then
        printf '%s\n' "$key" >>"$excludes_file"
      fi
    done <"$file"
  done

  sort -u "$excludes_file" -o "$excludes_file"
}

query_github_repos() {
  local remote_file="$1"
  local cache_file
  local cache_dir
  local tmp_cache

  cache_file="$(cache_file_path)"
  cache_dir="$(dirname "$cache_file")"

  if cache_is_fresh "$cache_file"; then
    log_info "using cached GitHub repo list: $cache_file"
  else
    log_info "querying GitHub repos for owner $OWNER (limit $LIMIT)"
    mkdir -p "$cache_dir"
    tmp_cache="$(mktemp "${cache_dir}/github-repos.XXXXXX")"
    if gh repo list "$OWNER" \
      --limit "$LIMIT" \
      --json name,nameWithOwner,isArchived,isFork,isPrivate,defaultBranchRef,sshUrl,url,pushedAt >"$tmp_cache"; then
      mv "$tmp_cache" "$cache_file"
      log_info "wrote GitHub repo cache: $cache_file"
    else
      rm -f "$tmp_cache"
      if [[ -s "$cache_file" ]]; then
        log_info "GitHub query failed; using stale repo cache: $cache_file"
      else
        error "GitHub query failed and no repo cache is available"
        return 1
      fi
    fi
  fi

  jq -r '
    .[]
    | [
        .nameWithOwner,
        .name,
        .sshUrl,
        .url,
        (.isArchived | tostring),
        (.isFork | tostring),
        (.isPrivate | tostring),
        (.defaultBranchRef.name // ""),
        (.pushedAt // "")
      ]
    | @tsv
  ' "$cache_file" >"$remote_file"

  log_info "loaded $(count_lines "$remote_file") GitHub repos for $OWNER"
}

write_expected_repos() {
  local remote_file="$1"
  local excludes_file="$2"
  local expected_file="$3"
  local excluded_file="$4"
  local full_name name ssh_url html_url archived fork private default_branch pushed_at
  local key reason

  : >"$expected_file"
  : >"$excluded_file"

  log_info "applying exclusions to GitHub repo list"

  while IFS=$'\t' read -r full_name name ssh_url html_url archived fork private default_branch pushed_at; do
    key="$(lowercase "$full_name")"
    reason=""

    if grep -Fxq "$key" "$excludes_file"; then
      reason="explicit"
    elif [[ "$EXCLUDE_ARCHIVED" == "true" && "$archived" == "true" ]]; then
      reason="archived"
    elif [[ "$EXCLUDE_FORKS" == "true" && "$fork" == "true" ]]; then
      reason="fork"
    fi

    if [[ -n "$reason" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$reason" "$full_name" "$name" "$ssh_url" "$html_url" "$archived" "$fork" "$private" "$default_branch" "$pushed_at" >>"$excluded_file"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$full_name" "$name" "$ssh_url" "$html_url" "$archived" "$fork" "$private" "$default_branch" "$pushed_at" >>"$expected_file"
    fi
  done <"$remote_file"

  log_info "expected repos after exclusions: $(count_lines "$expected_file"); excluded: $(count_lines "$excluded_file")"
}

scan_local_repos() {
  local local_file="$1"
  local status_file="$2"
  local dir top_level local_name origin full_name path_key

  : >"$local_file"
  : >"$status_file"

  log_info "scanning local repos under $ROOT_DIR"

  while IFS= read -r -d '' dir; do
    if ! top_level="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
      continue
    fi

    if [[ "$top_level" != "$dir" ]]; then
      continue
    fi

    local_name="$(basename "$dir")"
    log_info "checking local repo: $local_name"

    if origin="$(git -C "$dir" remote get-url origin 2>/dev/null)" &&
      full_name="$(github_remote_owner_repo "$origin")"; then
      path_key="$(lowercase "$full_name")"
    else
      origin="${origin:-<no origin>}"
      full_name="-"
      path_key="-"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$path_key" "$full_name" "$local_name" "$origin" "$dir" >>"$local_file"
    scan_repo_status "$dir" "$full_name" "$local_name" "$status_file"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  log_info "scanned $(count_lines "$local_file") local repos"
}

scan_repo_status() {
  local dir="$1"
  local full_name="$2"
  local local_name="$3"
  local status_file="$4"
  local fetch_state="skipped"
  local branch="DETACHED"
  local upstream=""
  local dirty_count="0"
  local ahead="0"
  local behind="0"
  local main_base="origin/main"
  local main_ahead="0"
  local main_behind="0"
  local main_state="no-origin-main"
  local state="current"
  local counts=""
  local main_counts=""
  local upstream_candidate=""

  if [[ "$FETCH" == "true" ]]; then
    log_info "fetching origin for $local_name"
    if git -C "$dir" fetch --prune --quiet origin 2>/dev/null; then
      fetch_state="ok"
    else
      fetch_state="failed"
      log_info "fetch failed for $local_name"
    fi
  fi

  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'DETACHED')"
  dirty_count="$(git -C "$dir" status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')"
  if upstream_candidate="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" &&
    [[ "$upstream_candidate" != "@{u}" ]]; then
    upstream="$upstream_candidate"
  fi

  if [[ -z "$upstream" ]]; then
    state="no-upstream"
  else
    counts="$(git -C "$dir" rev-list --left-right --count HEAD..."$upstream" 2>/dev/null || true)"
    if [[ -n "$counts" ]]; then
      read -r ahead behind <<<"$counts"
    fi

    if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
      state="diverged"
    elif [[ "$ahead" -gt 0 ]]; then
      state="ahead"
    elif [[ "$behind" -gt 0 ]]; then
      state="behind"
    else
      state="current"
    fi
  fi

  if [[ "$dirty_count" -gt 0 && "$state" == "current" ]]; then
    state="dirty"
  elif [[ "$dirty_count" -gt 0 ]]; then
    state="dirty+$state"
  fi

  if [[ "$fetch_state" == "failed" ]]; then
    state="fetch-failed+$state"
  fi

  if git -C "$dir" rev-parse --verify --quiet "$main_base" >/dev/null; then
    main_counts="$(git -C "$dir" rev-list --left-right --count HEAD..."$main_base" 2>/dev/null || true)"
    if [[ -n "$main_counts" ]]; then
      read -r main_ahead main_behind <<<"$main_counts"
    fi

    if [[ "$branch" == "main" && "$main_ahead" -eq 0 ]]; then
      main_state="on-main"
    elif [[ "$branch" == "main" ]]; then
      main_state="main-ahead"
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$full_name" "$local_name" "$branch" "${upstream:-}" "$dirty_count" "$ahead" "$behind" "$fetch_state" "$state" \
    "$main_base" "$main_ahead" "$main_behind" "$main_state" "$dir" >>"$status_file"
}

write_missing_and_extra() {
  local expected_file="$1"
  local local_file="$2"
  local missing_file="$3"
  local extra_file="$4"
  local expected_keys="$TMP_DIR/expected.keys"
  local local_keys="$TMP_DIR/local.keys"
  local full_name name ssh_url html_url archived fork private default_branch pushed_at
  local key path_key local_full local_name origin path

  awk -F $'\t' '{print tolower($1)}' "$expected_file" | sort -u >"$expected_keys"
  awk -F $'\t' '$1 != "-" {print tolower($1)}' "$local_file" | sort -u >"$local_keys"

  : >"$missing_file"
  : >"$extra_file"

  while IFS=$'\t' read -r full_name name ssh_url html_url archived fork private default_branch pushed_at; do
    key="$(lowercase "$full_name")"
    if ! grep -Fxq "$key" "$local_keys"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$full_name" "$name" "$ssh_url" "$html_url" "$archived" "$fork" "$private" "$default_branch" "$pushed_at" >>"$missing_file"
    fi
  done <"$expected_file"

  while IFS=$'\t' read -r path_key local_full local_name origin path; do
    if [[ "$path_key" == "-" ]] || ! grep -Fxq "$path_key" "$expected_keys"; then
      printf '%s\t%s\t%s\t%s\n' "$local_full" "$local_name" "$origin" "$path" >>"$extra_file"
    fi
  done <"$local_file"
}

count_lines() {
  local file="$1"

  wc -l <"$file" | tr -d ' '
}

count_status_where() {
  local status_file="$1"
  local expression="$2"

  awk -F $'\t' "$expression" "$status_file"
}

emit_table() {
  local remote_file="$1"
  local expected_file="$2"
  local excluded_file="$3"
  local local_file="$4"
  local missing_file="$5"
  local extra_file="$6"
  local status_file="$7"
  local attention_file="$TMP_DIR/attention.tsv"
  local github_count expected_count excluded_count local_count missing_count extra_count cloned_expected
  local dirty_count ahead_count behind_count diverged_count no_upstream_count fetch_failed_count on_main_count main_drift_count no_main_count

  github_count="$(count_lines "$remote_file")"
  expected_count="$(count_lines "$expected_file")"
  excluded_count="$(count_lines "$excluded_file")"
  local_count="$(count_lines "$local_file")"
  missing_count="$(count_lines "$missing_file")"
  extra_count="$(count_lines "$extra_file")"
  cloned_expected=$((expected_count - missing_count))

  dirty_count="$(count_status_where "$status_file" "\$5 > 0 {c++} END {print c+0}")"
  ahead_count="$(count_status_where "$status_file" "\$6 > 0 {c++} END {print c+0}")"
  behind_count="$(count_status_where "$status_file" "\$7 > 0 {c++} END {print c+0}")"
  diverged_count="$(count_status_where "$status_file" "\$6 > 0 && \$7 > 0 {c++} END {print c+0}")"
  no_upstream_count="$(count_status_where "$status_file" "\$4 == \"\" {c++} END {print c+0}")"
  fetch_failed_count="$(count_status_where "$status_file" "\$8 == \"failed\" {c++} END {print c+0}")"
  on_main_count="$(count_status_where "$status_file" "\$13 == \"on-main\" {c++} END {print c+0}")"
  main_drift_count="$(count_status_where "$status_file" "\$13 != \"on-main\" && \$13 != \"no-origin-main\" {c++} END {print c+0}")"
  no_main_count="$(count_status_where "$status_file" "\$13 == \"no-origin-main\" {c++} END {print c+0}")"

  printf 'GitHub owner: %s\n' "$OWNER"
  printf 'Local root:   %s\n' "$ROOT_DIR"
  printf 'Fetch:        %s\n' "$FETCH"
  printf '\n'
  printf '%-24s %s\n' "GitHub repos" "$github_count"
  printf '%-24s %s\n' "Excluded repos" "$excluded_count"
  printf '%-24s %s\n' "Expected clones" "$expected_count"
  printf '%-24s %s\n' "Cloned expected" "$cloned_expected"
  printf '%-24s %s\n' "Missing expected" "$missing_count"
  printf '%-24s %s\n' "Unexpected local" "$extra_count"
  printf '%-24s %s\n' "Local repos scanned" "$local_count"
  printf '%-24s %s\n' "Dirty worktrees" "$dirty_count"
  printf '%-24s %s\n' "Ahead of upstream" "$ahead_count"
  printf '%-24s %s\n' "Behind upstream" "$behind_count"
  printf '%-24s %s\n' "Diverged" "$diverged_count"
  printf '%-24s %s\n' "No upstream" "$no_upstream_count"
  printf '%-24s %s\n' "Fetch failures" "$fetch_failed_count"
  printf '%-24s %s\n' "On main at origin/main" "$on_main_count"
  printf '%-24s %s\n' "Branch/main drift" "$main_drift_count"
  printf '%-24s %s\n' "No origin/main" "$no_main_count"

  sort -t $'\t' -k1,1 "$missing_file" -o "$missing_file"
  if [[ -s "$missing_file" ]]; then
    printf '\nMissing expected clones\n'
    awk -F $'\t' '
      BEGIN {
        printf "%-58s %-7s %-5s %-8s %s\n", "REPO", "PRIVATE", "FORK", "DEFAULT", "PUSHED"
      }
      {
        printf "%-58s %-7s %-5s %-8s %s\n", $1, $7, $6, ($8 == "" ? "-" : $8), $9
      }
    ' "$missing_file"
  fi

  sort -t $'\t' -k2,2 "$extra_file" -o "$extra_file"
  if [[ -s "$extra_file" ]]; then
    printf '\nUnexpected local repos\n'
    awk -F $'\t' '
      BEGIN {
        printf "%-58s %-26s %s\n", "REMOTE", "LOCAL", "ORIGIN"
      }
      {
        printf "%-58s %-26s %s\n", $1, $2, $3
      }
    ' "$extra_file"
  fi

  if [[ "$SHOW_ALL" == "true" ]]; then
    sort -t $'\t' -k2,2 "$status_file" >"$attention_file"
  else
    awk -F $'\t' '$5 > 0 || $6 > 0 || $7 > 0 || $8 == "failed" || $4 == "" || $13 != "on-main"' "$status_file" |
      sort -t $'\t' -k2,2 >"$attention_file"
  fi

  if [[ -s "$attention_file" ]]; then
    printf '\nRepos needing attention\n'
    awk -F $'\t' '
      BEGIN {
        printf "%-44s %-28s %5s %6s %-24s %-34s %5s %5s %6s %-6s %-24s %s\n", "REPO", "BRANCH", "MAIN+", "MAIN-", "MAIN_STATE", "UPSTREAM", "DIRTY", "AHEAD", "BEHIND", "FETCH", "STATE", "PATH"
      }
      {
        repo = ($1 == "-" ? $2 : $1)
        upstream = ($4 == "" ? "-" : $4)
        printf "%-44s %-28s %5s %6s %-24s %-34s %5s %5s %6s %-6s %-24s %s\n", repo, $3, $11, $12, $13, upstream, $5, $6, $7, $8, $9, $14
      }
    ' "$attention_file"
  fi
}

emit_tsv() {
  local remote_file="$1"
  local expected_file="$2"
  local excluded_file="$3"
  local local_file="$4"
  local missing_file="$5"
  local extra_file="$6"
  local status_file="$7"

  printf '# summary\n'
  printf 'metric\tvalue\n'
  printf 'github_owner\t%s\n' "$OWNER"
  printf 'local_root\t%s\n' "$ROOT_DIR"
  printf 'fetch\t%s\n' "$FETCH"
  printf 'github_repos\t%s\n' "$(count_lines "$remote_file")"
  printf 'excluded_repos\t%s\n' "$(count_lines "$excluded_file")"
  printf 'expected_clones\t%s\n' "$(count_lines "$expected_file")"
  printf 'missing_expected\t%s\n' "$(count_lines "$missing_file")"
  printf 'unexpected_local\t%s\n' "$(count_lines "$extra_file")"
  printf 'local_repos_scanned\t%s\n' "$(count_lines "$local_file")"

  printf '# missing\n'
  printf 'repo\tname\tssh_url\thtml_url\tarchived\tfork\tprivate\tdefault_branch\tpushed_at\n'
  sort -t $'\t' -k1,1 "$missing_file"

  printf '# unexpected_local\n'
  printf 'remote\tlocal\torigin\tpath\n'
  sort -t $'\t' -k2,2 "$extra_file"

  printf '# status\n'
  printf 'remote\tlocal\tbranch\tupstream\tdirty_count\tahead\tbehind\tfetch\tstate\tmain_base\tmain_ahead\tmain_behind\tmain_state\tpath\n'
  sort -t $'\t' -k2,2 "$status_file"
}

main() {
  local excludes_file remote_file expected_file excluded_file local_file status_file missing_file extra_file

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

  require_command gh
  require_command git
  require_command jq

  if [[ ! -d "$ROOT_DIR" ]]; then
    error "Root directory not found: $ROOT_DIR"
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  excludes_file="$TMP_DIR/excludes.txt"
  remote_file="$TMP_DIR/remote.tsv"
  expected_file="$TMP_DIR/expected.tsv"
  excluded_file="$TMP_DIR/excluded.tsv"
  local_file="$TMP_DIR/local.tsv"
  status_file="$TMP_DIR/status.tsv"
  missing_file="$TMP_DIR/missing.tsv"
  extra_file="$TMP_DIR/extra.tsv"

  write_excludes "$excludes_file"
  query_github_repos "$remote_file"
  write_expected_repos "$remote_file" "$excludes_file" "$expected_file" "$excluded_file"
  scan_local_repos "$local_file" "$status_file"
  write_missing_and_extra "$expected_file" "$local_file" "$missing_file" "$extra_file"

  case "$FORMAT" in
    table)
      emit_table "$remote_file" "$expected_file" "$excluded_file" "$local_file" "$missing_file" "$extra_file" "$status_file"
      ;;
    tsv)
      emit_tsv "$remote_file" "$expected_file" "$excluded_file" "$local_file" "$missing_file" "$extra_file" "$status_file"
      ;;
  esac
}

main "$@"
